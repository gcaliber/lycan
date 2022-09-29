#[cfg(unix)]
use std::io::{Read, Seek};
use std::path::{Path};
use std::{fs, io};

pub use zip::result::ZipError;

pub fn extract<S: Read + Seek>(source: S, target_dir: &Path,) -> anyhow::Result<()> {
    if !target_dir.exists() {
        fs::create_dir(&target_dir)?;
    }

    let mut archive = zip::ZipArchive::new(source)?;

    for i in 0..archive.len() {
        let mut file = archive.by_index(i)?;
        let relative_path = file.mangled_name();

        if relative_path.to_string_lossy().is_empty() {
            // Top-level directory
            continue;
        }

        let mut outpath = target_dir.to_path_buf();
        outpath.push(relative_path);

        if file.name().ends_with('/') {
            fs::create_dir_all(&outpath)?;
        } else {
            if let Some(p) = outpath.parent() {
                if !p.exists() {
                    fs::create_dir_all(&p)?;
                }
            }
            let mut outfile = fs::File::create(&outpath)?;
            io::copy(&mut file, &mut outfile)?;
        }
    }

    Ok(())
}