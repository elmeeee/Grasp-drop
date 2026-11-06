use std::env;

fn main() {
    // Generate a C header for the FFI surface when cbindgen is available.
    let crate_dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    let config = cbindgen::Config {
        language: cbindgen::Language::C,
        cpp_compat: true,
        ..Default::default()
    };

    let _ = cbindgen::Builder::new()
        .with_crate(crate_dir)
        .with_config(config)
        .generate()
        .map(|bindings| {
            bindings.write_to_file("include/grasp_core.h");
        });
}
