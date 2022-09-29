use std::{env, fs};
use std::fs::File;
use std::path::{Path, PathBuf};

use fs_extra::dir::{CopyOptions};
use regex::{Regex};
use reqwest::header::{HeaderMap, CONTENT_DISPOSITION};
use serde::{Deserialize, Serialize};
use serde_json::{Value};

use crate::config::{Config};
use crate::unzip;

// #[serde(skip_serializing)]

#[derive(Serialize, Deserialize, Debug, Clone)]
pub enum AddonKind {
  GithubRelease,
  GithubRepo {branch: String},
  TukuiMain,
  TukuiAddon, 
  Gitlab,
  WowInt,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct Addon {
  pub project: String,
  pub version: Option<String>,
  pub name: Option<String>,
  pub kind: AddonKind,
  pub id: u32,
  pub dirs: Option<Vec<String>>,
  #[serde(skip_serializing)]
  pub download_url: Option<String>,
  #[serde(skip_serializing)]
  pub filename: Option<String>,
}

impl Addon {
  pub fn new(project: String, kind: AddonKind) -> Self {
    Self { 
      project: project, 
      id: 0,
      name: None,
      version: None,
      dirs: None,
      kind: kind,
      download_url: None,
      filename: None,
    }
  }

// cargo run -- -i https://github.com/Stanzilla/AdvancedInterfaceOptions https://github.com/Tercioo/Plater-Nameplates/tree/master https://gitlab.com/siebens/legacy/autoactioncam https://www.tukui.org/download.php?ui=tukui https://www.tukui.org/addons.php?id=209 https://www.wowinterface.com/downloads/info24608-HekiliPriorityHelper.html

// https://github.com/Stanzilla/AdvancedInterfaceOptions
// https://github.com/Tercioo/Plater-Nameplates/tree/master
// https://gitlab.com/siebens/legacy/autoactioncam
// https://www.tukui.org/download.php?ui=elvui
// https://www.tukui.org/addons.php?id=209
// https://www.wowinterface.com/downloads/info24608-HekiliPriorityHelper.html

  pub fn latest_url(&self) -> String {
    match &self.kind {
      AddonKind::GithubRelease => format!("https://api.github.com/repos/{}/releases/latest", self.project),
      AddonKind::GithubRepo{branch} => format!("https://api.github.com/repos/{}/commits/{}", self.project, branch),
      AddonKind::TukuiMain => format!("https://www.tukui.org/api.php?ui={}", self.project),
      AddonKind::TukuiAddon => String::from("https://www.tukui.org/api.php?addons"),
      AddonKind::Gitlab => format!("https://gitlab.com/api/v4/projects/{}/releases", self.project.replace("/", "%2F")),
      AddonKind::WowInt => format!("https://api.mmoui.com/v3/game/WOW/filedetails/{}.json", self.project),
    }
  }

  pub fn set_version(&mut self, json: &Value) -> bool {
    let old_version = self.version.as_ref().unwrap().clone();
    self.version = match &self.kind {
      AddonKind::GithubRelease => {
        let v = json["tag_name"].as_str().unwrap();
        Some(String::from(if v != "" {v} else {json["name"].as_str().unwrap()}))
      },
      AddonKind::GithubRepo{..} => Some(String::from(json["sha"].as_str().unwrap())),
      AddonKind::TukuiMain => Some(String::from(json["version"].as_str().unwrap())),
      AddonKind::TukuiAddon => {
        let mut result: &str = "";
        for item in json.as_array().unwrap() {
          if item["id"].as_str().unwrap() == self.project {
            result = item["version"].as_str().unwrap();
          }
        }
        assert!(result != "");
        Some(String::from(result))
      },
      AddonKind::Gitlab => {
        let v = json[0]["tag_name"].as_str().unwrap();
        Some(String::from(if v != "" {v} else {json[0]["name"].as_str().unwrap()}))
      },
      AddonKind::WowInt => Some(String::from(json[0]["UIVersion"].as_str().unwrap())),
    };
    self.version.as_ref().unwrap().as_str() == old_version
  }

  pub fn set_download_url(&mut self, json: &Value) {
    self.download_url = Some(match &self.kind {
      AddonKind::GithubRelease => {
        let assets = json["assets"].as_array();
        match assets {
          Some(items) => {
            let mut result: &str = "";
            for item in items {
              if item["content_type"].as_str().unwrap() == "application/json" { continue }
              let url = item["browser_download_url"].as_str().unwrap();
              let lc = url.to_lowercase();
              if ["bcc", "tbc", "wotlk", "wrath", "classic"].iter().any(|&s| !lc.contains(s)) {
                result = url;
              }
            }
            assert!(result != "");
            String::from(result)
          },
          None => String::from(json["zipball_url"].as_str().unwrap())
        }
      },
      AddonKind::GithubRepo { branch } => format!("https://www.github.com/{}/archive/refs/heads/{}.zip", self.project, branch),
      AddonKind::TukuiMain => String::from(json["url"].as_str().unwrap()),
      AddonKind::TukuiAddon => {
        let mut result: &str = "";
        for item in json.as_array().unwrap() {
          if item["id"].as_str().unwrap() == self.project {
            result = item["url"].as_str().unwrap();
          }
        }
        assert!(result != "");
        String::from(result)
      },
      AddonKind::Gitlab => {
        let mut result: &str = "";
        let sources = json[0]["assets"]["sources"].as_array().unwrap();
        for s in sources {
          if s["format"].as_str().unwrap() == "zip" {
            result = s["url"].as_str().unwrap()
          }
        }
        String::from(result)
      },
      AddonKind::WowInt => String::from(json[0]["UIDownload"].as_str().unwrap()),
    });
  }

  pub fn set_name(&mut self, json: &Value) {
    self.name = Some(String::from(match &self.kind {
      AddonKind::GithubRelease | AddonKind::GithubRepo{..} | AddonKind::Gitlab => self.project.split('/').last().unwrap(),
      AddonKind::TukuiMain => json["name"].as_str().unwrap(),
      AddonKind::TukuiAddon => {
       let mut result: &str = "";
        for item in json.as_array().unwrap() {
          if item["id"].as_str().unwrap() == self.project {
            result = item["name"].as_str().unwrap();
          }
        }
        assert!(result != "");
        result
      },
      AddonKind::WowInt => json[0]["UIName"].as_str().unwrap(),
    }))
  }

  pub fn set_filename(&mut self, headers: &HeaderMap) {
    let filename = if headers.contains_key(CONTENT_DISPOSITION) {
      headers[CONTENT_DISPOSITION].to_str().unwrap()
        .split("=").into_iter().collect::<Vec<&str>>()
        .last().copied().unwrap().trim_matches(&['\'', '"'] as &[_])
    }
    else {
      self.download_url.as_ref().unwrap()
        .split("/").into_iter().collect::<Vec<&str>>()
        .last().copied().unwrap()
    };
    self.filename = Some(String::from(filename));
  }

  fn extract(&self) -> anyhow::Result<PathBuf> {
    let mut archive_path = env::temp_dir();
    archive_path.push(self.filename.as_ref().expect("PANIC: Unable to set archive_path"));
    
    let mut extract_path = env::temp_dir();
    extract_path.push(archive_path.file_stem().expect("PANIC: Unable to set extract_path"));

    let archive = File::open(archive_path)?;
    unzip::extract(&archive, &extract_path)?;
    Ok(extract_path)
  }
  
  pub fn install(&mut self, config: &Config, installed_addons: &Vec<Addon>) -> anyhow::Result<()> {
    let extract_path = self.extract()?;
    if let Some(installed) = self.get_installed(installed_addons) {
      self.id = installed.id;
      installed.remove()?;
    }
    self.dirs = Some(move_addon_dirs(&extract_path, &config.addon_dir)?);
    Ok(())
  }

  fn get_installed(&self, installed_addons: &Vec<Addon>) -> Option<Addon> {
    for a in installed_addons {
      if self == a {
        return Some(a.clone())
      }
    }
    None
  }

  fn remove(&self) -> anyhow::Result<()> {
    for dir in self.dirs.as_ref().unwrap() {
      fs::remove_dir_all(dir)?;
    }
    Ok(())
  }

  pub fn set_id(&mut self, mut ids: Vec<u32>) -> Vec<u32>{
    if self.id != 0 { return ids; }
    
    let mut i = 1;
    loop {
      if ids.contains(&i) { 
        i += 1;
        continue}
      else {
        self.id = i;
        ids.push(i);
        break;
      }
    }
    ids
  }
  

}

impl PartialEq for Addon {
  fn eq(&self, other: &Self) -> bool {
      self.project == other.project
  }
}

fn get_subdirs<P: AsRef<Path>>(path: P) -> anyhow::Result<Vec<PathBuf>> {
  let result = path.as_ref().read_dir()?
    .filter_map(|r| {
      let d = r.expect("PANIC: Error reading directory");
      if d.file_type().unwrap().is_dir() {
        return Some(d.path());
      }
      None
    }).collect();

    // println!("found subdirs {:?}", result);

  Ok(result)
}

fn process_tocs(path: &PathBuf) -> anyhow::Result<Option<PathBuf>> {
  for item in fs::read_dir(path)? {
    let d = item?;
    let kind = d.file_type()?;
    if kind.is_file() {
      if let Some(ext) = d.path().extension() {
        if ext == "toc" {
          let re = Regex::new(r#"(?P<head>.+?)(?:$|[-_](?i:mainline|wrath|tbc|vanilla|wotlkc?|bcc|classic))"#).unwrap();
          let dpath = d.path();
          let caps = re.captures(dpath.file_stem().unwrap().to_str().unwrap()).expect("PANIC: No capture available.");
          let toc_name = caps.name("head").expect("PANIC: No capture named 'head'").as_str();
          let mut corrected = path.parent().unwrap().to_path_buf();
          corrected.push(toc_name);
          fs::rename(path, &corrected)?;
          return Ok(Some(corrected));
        }
      } 
    }
  }
  Ok(None)
}

fn get_addon_dirs(extract_path: &PathBuf) -> anyhow::Result<Vec<PathBuf>> {
  let mut current = extract_path.to_path_buf();
  let mut first_pass = true;

  loop {
    if let Some(path) = process_tocs(&current)? {
      if first_pass {
        return Ok(vec![path]);
      } else {
        let t = get_subdirs(current.parent().unwrap());
        // println!("returning subdirs {:?}", t);
        return t;
      }
    } else {
      for item in fs::read_dir(&current)? {
        let d = item?;
        if d.file_type()?.is_dir() {
          current = d.path();
          continue;
        }
      }
    }
    first_pass = false;
  }
}

fn move_addon_dirs(extract_dir: &PathBuf, dest: &Path)  -> anyhow::Result<Vec<String>> {
  let result = get_addon_dirs(extract_dir)?.into_iter()
    .flat_map(|source| {
      let name = source.file_name().unwrap();
      // println!("source:  {:?}\ntarget:  {:?}", source, dest);
      let options = CopyOptions::new();
      let v = vec![&source];
      fs_extra::dir::create_all(&dest, false)?;
      fs_extra::move_items(&v, dest, &options)?;
      anyhow::Ok(String::from(name.to_str().unwrap()))
    }).collect();
  
  Ok(result)
}