fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_build::configure()
    .build_server(false)
    // .out_dir("src/kobe")
    .compile(
        &["proto/kobe.proto"],
        &["proto"],
    )?;
    Ok(())
}