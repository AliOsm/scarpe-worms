#![windows_subsystem = "windows"]

use std::{
    env,
    fs::{self, OpenOptions},
    io::{self, Write},
    os::windows::process::CommandExt,
    path::PathBuf,
    process::{self, Command, Stdio},
    time::{SystemTime, UNIX_EPOCH},
};

#[link(name = "user32")]
extern "system" {
    fn MessageBoxW(
        window: *mut std::ffi::c_void,
        text: *const u16,
        title: *const u16,
        flags: u32,
    ) -> i32;
}

fn logs() -> PathBuf {
    env::var_os("BURROW_LOG_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            env::var_os("LOCALAPPDATA")
                .map(PathBuf::from)
                .unwrap_or_else(|| {
                    env::var_os("USERPROFILE")
                        .map(PathBuf::from)
                        .unwrap_or_else(env::temp_dir)
                        .join("AppData/Local")
                })
                .join("Burrow Brigade/Logs")
        })
}

fn launch() -> io::Result<i32> {
    let exe = env::current_exe()?;
    let root = exe
        .parent()
        .ok_or_else(|| io::Error::other("Missing application directory"))?;
    let res = root.join("resources");
    let runtime = res.join("ruby");
    let ruby = runtime.join("bin/rubyw.exe");
    let log_dir = logs();
    fs::create_dir_all(&log_dir)?;
    let path = log_dir.join("launcher.log");
    if fs::metadata(&path).is_ok_and(|m| m.len() > 5 * 1024 * 1024) {
        let previous = log_dir.join("launcher.log.1");
        if previous.exists() {
            fs::remove_file(&previous)?;
        }
        fs::rename(&path, previous)?;
    }
    let mut log = OpenOptions::new().create(true).append(true).open(path)?;
    writeln!(
        log,
        "\nBurrow Brigade launch at Unix {}",
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs()
    )?;
    if !ruby.is_file()
        || !res.join("boot.rb").is_file()
        || !root.join("scarpe-native.exe").is_file()
    {
        return Err(io::Error::other(
            "Application files are missing. Extract the complete ZIP or reinstall Burrow Brigade.",
        ));
    }
    let mut libs: Vec<PathBuf> = ["lib", "lacci/lib", "scarpe-components/lib"]
        .iter()
        .map(|p| res.join("scarpe").join(p))
        .collect();
    libs.push(res.join("app/lib"));
    for gem in ["ffi", "chunky_png", "base64", "logger", "fastimage"] {
        libs.push(res.join("gems").join(gem).join("lib"));
    }
    let mut command = Command::new(&ruby);
    let inherited_path = env::var_os("PATH").unwrap_or_default();
    let mut search_paths = vec![runtime.join("bin")];
    search_paths.extend(env::split_paths(&inherited_path));
    let runtime_path = env::join_paths(search_paths).map_err(io::Error::other)?;
    command
        .arg("-EUTF-8")
        .arg(res.join("boot.rb"))
        .args(env::args_os().skip(1))
        .env("RUBYLIB", env::join_paths(libs).map_err(io::Error::other)?)
        .env("BURROW_RUBY", &ruby)
        .env("SCARPE_NATIVE_BIN", root.join("scarpe-native.exe"))
        .env("PATH", runtime_path)
        .env("GEM_HOME", runtime.join("lib/ruby/gems/4.0.0"))
        .env("GEM_PATH", runtime.join("lib/ruby/gems/4.0.0"))
        .env("SSL_CERT_FILE", runtime.join("lib/ruby/4.0.0/etc/ssl/cert.pem"))
        .env_remove("SSL_CERT_DIR");
    for key in [
        "RUBYOPT",
        "BUNDLE_GEMFILE",
        "BUNDLE_PATH",
        "BUNDLE_BIN_PATH",
        "BUNDLER_SETUP",
        "RUBYGEMS_GEMDEPS",
    ] {
        command.env_remove(key);
    }
    // No invoking console can override Ruby's UTF-8 manifest. The rubyw GUI
    // interpreter also keeps host/terrain children from allocating consoles.
    let status = command
        .current_dir(root)
        .creation_flags(0x00000008)
        .stdin(Stdio::null())
        .stdout(log.try_clone()?)
        .stderr(log)
        .status()?;
    Ok(status.code().unwrap_or(1))
}

fn main() {
    let (code, error) = match launch() {
        Ok(0) => return,
        Ok(code) => (
            code,
            format!("The game exited with code {code} (0x{:08X}).", code as u32),
        ),
        Err(error) => (1, error.to_string()),
    };
    let path = logs().join("launcher.log");
    if let Ok(mut log) = OpenOptions::new().create(true).append(true).open(&path) {
        let _ = writeln!(log, "Launcher: {error}");
    }
    eprintln!("Burrow Brigade: {error}\nLog: {}", path.display());
    if env::var("SCARPE_NATIVE_HEADLESS").as_deref() != Ok("1")
        && env::var_os("BURROW_WINDOWS_PROBE").is_none()
    {
        let text: Vec<u16> = format!(
            "Burrow Brigade could not start.\n\n{error}\n\nLog: {}",
            path.display()
        )
        .encode_utf16()
        .chain(Some(0))
        .collect();
        let title: Vec<u16> = "Burrow Brigade".encode_utf16().chain(Some(0)).collect();
        unsafe {
            MessageBoxW(std::ptr::null_mut(), text.as_ptr(), title.as_ptr(), 0x10);
        }
    }
    process::exit(code);
}
