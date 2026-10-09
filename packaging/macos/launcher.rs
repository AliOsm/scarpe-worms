// A Mach-O bundle entry point; all paths derive from the installed app location.
use std::{env, io, os::unix::process::CommandExt, process::Command};

fn main() -> io::Result<()> {
    let executable = env::current_exe()?;
    let contents = executable.parent().unwrap().parent().unwrap();
    Err(Command::new("/bin/bash")
        .arg(contents.join("Resources/launch.sh"))
        .args(env::args_os().skip(1))
        .exec())
}
