//! Build script for kaz-sign-sys
//!
//! Compiles the KAZ-SIGN C library and generates Rust FFI bindings.

use std::env;
use std::path::PathBuf;

fn main() {
    println!("cargo:rerun-if-changed=vendor/");
    println!("cargo:rerun-if-changed=build.rs");

    #[allow(unused_variables)]
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());

    // Compile the C library
    let mut build = cc::Build::new();
    build
        .file("vendor/src/sign.c")
        .file("vendor/src/kdf.c")
        .file("vendor/src/security.c")
        .file("vendor/src/nist_wrapper.c")
        .include("vendor/include")
        .define("KAZ_SECURITY_LEVEL", "256")
        .warnings(false);

    // Platform-specific compiler flags
    let target = env::var("TARGET").unwrap_or_default();
    if target.contains("msvc") {
        // MSVC flags
        build.flag("/O2");
    } else {
        // GCC/Clang flags
        build.flag("-O3");
        build.flag("-fPIC");
    }

    // Platform-specific OpenSSL configuration
    configure_openssl(&mut build);

    build.compile("kaz_sign");

    // Link OpenSSL
    println!("cargo:rustc-link-lib=crypto");

    // Generate bindings
    #[cfg(feature = "generate-bindings")]
    generate_bindings(&out_dir);
}

fn configure_openssl(build: &mut cc::Build) {
    #[cfg(target_os = "macos")]
    {
        if let Ok(output) = std::process::Command::new("brew")
            .args(["--prefix", "openssl@3"])
            .output()
        {
            if output.status.success() {
                let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
                build.include(format!("{}/include", path));
                println!("cargo:rustc-link-search=native={}/lib", path);
                return;
            }
        }
        for path in &["/usr/local/opt/openssl@3", "/opt/homebrew/opt/openssl@3"] {
            if std::path::Path::new(path).exists() {
                build.include(format!("{}/include", path));
                println!("cargo:rustc-link-search=native={}/lib", path);
                return;
            }
        }
    }

    #[cfg(target_os = "windows")]
    {
        // Check for explicit include/lib dirs first, then fall back to OPENSSL_DIR
        if let Ok(include_dir) = env::var("OPENSSL_INCLUDE_DIR") {
            build.include(&include_dir);
        } else {
            let openssl_dir = env::var("OPENSSL_DIR")
                .unwrap_or_else(|_| "C:\\OpenSSL".to_string());
            build.include(format!("{}\\include", openssl_dir));
        }

        if let Ok(lib_dir) = env::var("OPENSSL_LIB_DIR") {
            println!("cargo:rustc-link-search=native={}", lib_dir);
        } else {
            let openssl_dir = env::var("OPENSSL_DIR")
                .unwrap_or_else(|_| "C:\\OpenSSL".to_string());
            println!("cargo:rustc-link-search=native={}\\lib", openssl_dir);
        }
    }

    #[cfg(target_os = "linux")]
    {
        if let Ok(lib) = pkg_config::probe_library("openssl") {
            for path in lib.include_paths {
                build.include(path);
            }
        } else {
            build.include("/usr/include");
            println!("cargo:rustc-link-search=native=/usr/lib/x86_64-linux-gnu");
        }
    }
}

#[cfg(feature = "generate-bindings")]
fn generate_bindings(out_dir: &PathBuf) {
    let bindings = bindgen::Builder::default()
        .header("vendor/include/kaz/sign.h")
        .header("vendor/include/kaz/kdf.h")
        .parse_callbacks(Box::new(bindgen::CargoCallbacks::new()))
        .allowlist_function("kaz_sign_.*")
        .allowlist_function("kaz_hkdf.*")
        .allowlist_function("kaz_kdf_.*")
        .allowlist_type("kaz_sign_.*")
        .allowlist_var("KAZ_SIGN_.*")
        .allowlist_var("KAZ_KDF_.*")
        .allowlist_var("KAZ_LEVEL_.*")
        .derive_debug(true)
        .derive_default(true)
        .generate()
        .expect("Unable to generate bindings");

    bindings
        .write_to_file(out_dir.join("bindings.rs"))
        .expect("Couldn't write bindings!");
}
