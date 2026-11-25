//! What a host adapter answers when it is asked directly: the feature
//! queries this layer reads, the resources it has to create, and the
//! descriptor heaps the title's sizes need.
//!
//! `#101` says the card loses the device where WARP runs. Before believing a
//! run, ask the adapter itself:
//!
//! ```text
//! cargo run -p victory-gpu --example d3d12_probe                 # the card
//! VICTORY_PROBE_WARP=1 cargo run -p victory-gpu --example d3d12_probe
//! ```
//!
//! Every line is one question and one answer, so two runs `diff` cleanly. A
//! refusal prints the HRESULT. Nothing here creates a window or a queue: it
//! is the capability surface, not a renderer.

#[cfg(not(windows))]
fn main() {
    println!("a window host only");
}

#[cfg(windows)]
fn main() {
    probe::run();
}

#[cfg(windows)]
mod probe {
    use std::ffi::c_void;

    use windows::core::Interface;
    use windows::Win32::Foundation::E_FAIL;
    use windows::Win32::Graphics::Direct3D::D3D_FEATURE_LEVEL_12_0;
    use windows::Win32::Graphics::Direct3D12::*;
    use windows::Win32::Graphics::Dxgi::Common::*;
    use windows::Win32::Graphics::Dxgi::*;

    /// Asks one feature query and prints the words it wrote.
    macro_rules! ask {
        ($device:expr, $name:literal, $feature:expr, $out:expr) => {{
            let out = &mut $out;
            let (at, bytes) = (out as *mut _ as *mut c_void, size_of_val(out) as u32);
            // SAFETY: the structure's own address and size.
            let r = unsafe { $device.CheckFeatureSupport($feature, at, bytes) };
            match r {
                Ok(()) => println!(
                    "{:<28} ok    {:?}",
                    $name,
                    // The words, so a layout this tree does not know still
                    // shows its answer.
                    // SAFETY: the query wrote the structure.
                    unsafe { std::slice::from_raw_parts(at.cast::<u32>(), bytes as usize / 4) }
                ),
                Err(e) => println!("{:<28} {:#010x} {}", $name, e.code().0, e.message()),
            }
        }};
    }

    pub fn run() {
        let warp = std::env::var_os("VICTORY_PROBE_WARP").is_some();
        // SAFETY: plain DXGI and D3D12 calls with valid descriptions.
        unsafe {
            let factory: IDXGIFactory4 = match CreateDXGIFactory2(DXGI_CREATE_FACTORY_FLAGS(0)) {
                Ok(f) => f,
                Err(e) => {
                    println!("no DXGI factory: {e}");
                    return;
                }
            };
            let adapter: IDXGIAdapter = if warp {
                match factory.EnumWarpAdapter() {
                    Ok(a) => a,
                    Err(e) => {
                        println!("no WARP adapter: {e}");
                        return;
                    }
                }
            } else {
                match factory.EnumAdapters1(0) {
                    Ok(a) => a.cast().unwrap_or_else(|_| unreachable!()),
                    Err(e) => {
                        println!("no adapter: {e}");
                        return;
                    }
                }
            };
            match adapter.cast::<IDXGIAdapter1>().and_then(|a| a.GetDesc1()) {
                Ok(desc) => println!(
                    "adapter                      {} ({:04x}:{:04x} flags={:#x} vram={} MB)",
                    String::from_utf16_lossy(&desc.Description).trim_end_matches(char::from(0)).to_owned(),
                    desc.VendorId,
                    desc.DeviceId,
                    desc.Flags,
                    desc.DedicatedVideoMemory >> 20
                ),
                Err(e) => println!("adapter                      ? ({e})"),
            }
            let mut device: Option<ID3D12Device> = None;
            if let Err(e) = D3D12CreateDevice(&adapter, D3D_FEATURE_LEVEL_12_0, &mut device) {
                println!("no D3D12 device: {e}");
                return;
            }
            let Some(device) = device else {
                println!("no D3D12 device");
                return;
            };

            // The queries this layer reads, plus the ones a failing run makes
            // one suspect.
            ask!(device, "D3D12_OPTIONS", D3D12_FEATURE_D3D12_OPTIONS, D3D12_FEATURE_DATA_D3D12_OPTIONS::default());
            ask!(device, "D3D12_OPTIONS1 (waves)", D3D12_FEATURE_D3D12_OPTIONS1, D3D12_FEATURE_DATA_D3D12_OPTIONS1::default());
            ask!(device, "D3D12_OPTIONS5", D3D12_FEATURE_D3D12_OPTIONS5, D3D12_FEATURE_DATA_D3D12_OPTIONS5::default());
            ask!(device, "D3D12_OPTIONS7 (mesh)", D3D12_FEATURE_D3D12_OPTIONS7, D3D12_FEATURE_DATA_D3D12_OPTIONS7::default());
            ask!(device, "D3D12_OPTIONS11", D3D12_FEATURE_D3D12_OPTIONS11, D3D12_FEATURE_DATA_D3D12_OPTIONS11::default());
            ask!(device, "SHADER_MODEL", D3D12_FEATURE_SHADER_MODEL, D3D12_FEATURE_DATA_SHADER_MODEL { HighestShaderModel: D3D_SHADER_MODEL_6_8 });
            ask!(device, "ARCHITECTURE1", D3D12_FEATURE_ARCHITECTURE1, D3D12_FEATURE_DATA_ARCHITECTURE1 { NodeIndex: 0, ..Default::default() });
            ask!(device, "GPU_VIRTUAL_ADDRESS", D3D12_FEATURE_GPU_VIRTUAL_ADDRESS_SUPPORT, D3D12_FEATURE_DATA_GPU_VIRTUAL_ADDRESS_SUPPORT::default());

            // The descriptor heap the title's view heap needs: 1,245,184
            // slots, and the 2^18 dynamic slots this layer adds behind them.
            // D3D12 documents 1,000,000 for tier 2; WARP made 1,507,328.
            println!();
            for slots in [
                737_855u32,
                934_464,
                999_999,
                1_000_000,
                1_000_001,
                1_245_184,
                1_507_328,
            ] {
                let made: windows::core::Result<ID3D12DescriptorHeap> = device.CreateDescriptorHeap(
                    &D3D12_DESCRIPTOR_HEAP_DESC {
                        Type: D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV,
                        NumDescriptors: slots,
                        Flags: D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE,
                        NodeMask: 0,
                    },
                );
                match made {
                    Ok(_) => println!("view heap {slots:>9}            ok"),
                    Err(e) => println!("view heap {slots:>9}            {:#010x} {}", e.code().0, e.message()),
                }
            }

            // The resources a first-run walk creates: the console's formats,
            // both as a plain texture and as the castable twin the layer
            // makes first (`resource.rs`, "the host refuses castable
            // formats"). Format numbers are DXGI's.
            println!();
            let formats = [
                ("B4G4R4A4_UNORM", 115u32, DXGI_FORMAT_B4G4R4A4_UNORM),
                ("R32G8X24_TYPELESS", 19, DXGI_FORMAT_R32G8X24_TYPELESS),
                ("R8G8B8A8_UNORM", 28, DXGI_FORMAT_R8G8B8A8_UNORM),
                ("D32_FLOAT", 40, DXGI_FORMAT_D32_FLOAT),
                ("BC7_UNORM", 98, DXGI_FORMAT_BC7_UNORM),
            ];
            for (name, number, format) in formats {
                // What the host says the format can be. These are the bits
                // `resource::kept_flags` reads before it asks for a texture.
                ask!(
                    device,
                    "FORMAT_SUPPORT",
                    D3D12_FEATURE_FORMAT_SUPPORT,
                    D3D12_FEATURE_DATA_FORMAT_SUPPORT {
                        Format: format,
                        Support1: D3D12_FORMAT_SUPPORT1(0),
                        ..Default::default()
                    }
                );
                for (flags_name, flags) in [
                    ("none", D3D12_RESOURCE_FLAG_NONE),
                    ("rt", D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET),
                    ("uav", D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS),
                ] {
                    let desc = D3D12_RESOURCE_DESC {
                        Dimension: D3D12_RESOURCE_DIMENSION_TEXTURE2D,
                        Alignment: 0,
                        Width: 2560,
                        Height: 1440,
                        DepthOrArraySize: 1,
                        MipLevels: 1,
                        Format: format,
                        SampleDesc: DXGI_SAMPLE_DESC { Count: 1, Quality: 0 },
                        Layout: D3D12_TEXTURE_LAYOUT_UNKNOWN,
                        Flags: flags,
                    };
                    let mut made: Option<ID3D12Resource> = None;
                    let r = device.CreateCommittedResource(
                        &D3D12_HEAP_PROPERTIES {
                            Type: D3D12_HEAP_TYPE_DEFAULT,
                            ..Default::default()
                        },
                        D3D12_HEAP_FLAG_NONE,
                        &desc,
                        D3D12_RESOURCE_STATE_COMMON,
                        None,
                        &mut made,
                    );
                    match r {
                        Ok(()) => println!("2560x1440 {name:<18} {number:>3} {flags_name:<5} ok"),
                        Err(e) => println!(
                            "2560x1440 {name:<18} {number:>3} {flags_name:<5} {:#010x} {}",
                            e.code().0,
                            e.message()
                        ),
                    }
                }
            }
            let _ = E_FAIL;
            let _ = |p: *mut c_void| p;
        }
    }
}
