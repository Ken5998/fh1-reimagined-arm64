//! Forza Horizon 1: ReImagined launcher for ARM64 Linux handhelds (ArmadaOS on the
//! Retroid Pocket 6, or any aarch64 Linux): builds ReImagined, Forza Horizon (Xbox 360)
//! recompiled, from the player's own disc and title update with this repository's scripts,
//! keeps it up to date, plays it and adds it to Steam.

mod app;
mod tasks;

const HELP: &str = "Forza Horizon 1: ReImagined launcher for ARM64

Without options the launcher window opens. It builds Forza Horizon 1: ReImagined in
~/.local/share/FH1ReImagined-arm64 from your own Forza Horizon (Xbox 360) disc image
and Title Update 4, with the scripts of https://github.com/Ken5998/fh1-reimagined-arm64.

  --help     this text
  --version  the launcher's version";

fn main() {
    match std::env::args().nth(1).as_deref() {
        Some("--help" | "-h") => {
            println!("{HELP}");
            return;
        }
        Some("--version" | "-V") => {
            println!("{}", env!("CARGO_PKG_VERSION"));
            return;
        }
        _ => {}
    }

    let options = eframe::NativeOptions {
        viewport: eframe::egui::ViewportBuilder::default()
            .with_title("Forza Horizon ReImagined")
            .with_app_id("fh1-launcher")
            .with_inner_size([860.0, 620.0])
            .with_min_inner_size([640.0, 480.0]),
        ..Default::default()
    };
    let result = eframe::run_native(
        "Forza Horizon ReImagined",
        options,
        Box::new(|cc| {
            cc.egui_ctx.set_theme(eframe::egui::Theme::Dark);
            Ok(Box::new(app::LauncherApp::new(cc.egui_ctx.clone())))
        }),
    );
    if let Err(e) = result {
        eprintln!("The launcher window could not open: {e}");
        std::process::exit(1);
    }
}
