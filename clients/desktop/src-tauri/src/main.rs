// Prevents additional console window on Windows in release
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use securesharing_desktop::run;

fn main() {
    run();
}
