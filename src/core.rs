use std::{env, fs::{File, self}, io::Write, path::PathBuf};

use futures::{stream::{self, BufferUnordered}, StreamExt};
use reqwest::{Client, header::{CONTENT_TYPE, USER_AGENT}};
use serde_json::Value;

use crate::{addon::Addon, config::Config};

const CHROME_USER_AGENT: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/105.0.0.0 Safari/537.36";
const PARALLEL_REQUESTS: usize = 10;

pub async fn install(addons: Vec<Addon>, config: &Config) -> anyhow::Result<()> {
  let client = Client::new();
	let updates = stream::iter(addons)
		.map(|addon| {
			let url = addon.latest_url();
			let client = client.clone();
			tokio::spawn(async move {
				let json = client.get(url)
				.header(CONTENT_TYPE, "application/json")
				.header(USER_AGENT, CHROME_USER_AGENT)
				.send()
				.await.unwrap()
				.json::<Value>()
				.await;
				(addon, json)
			})
		})
		.buffer_unordered(PARALLEL_REQUESTS);

	let acc: Vec<Addon> = Vec::new();
	let addons = updates
		.fold(acc, |mut acc, u| async {
			match u {
				Ok((mut addon, json)) => {
					match json {
						Ok(json) => {
							addon.set_version(&json);
							addon.set_download_url(&json);
							addon.set_name(&json);
							acc.push(addon);
						},
						Err(e) => eprintln!("Got a reqwest::Error {}", e),		
					}
				},
				Err(e) => eprintln!("Got a tokio::JoinError: {}", e),
			}
			acc
		})
		.await;

	let downloads = stream::iter(addons)
		.map(|mut addon| {
			let client = client.clone();
			tokio::spawn(async move {
				let download_url = addon.download_url.as_ref().unwrap();
				let resp = client.get(download_url)
				.header(USER_AGENT, CHROME_USER_AGENT)
				.send()
				.await.unwrap();

				addon.set_filename(resp.headers());
				let bytes = resp.bytes().await;
				(addon, bytes)
			})
		})
		.buffer_unordered(PARALLEL_REQUESTS);

	let acc: Vec<Addon> = Vec::new();
	let addons = downloads
		.fold(acc, |mut acc, u| async {
			match u {
				Ok((addon, bytes)) => {
					match bytes {
						Ok(b) => {
							let mut path = env::temp_dir();
							path.push(addon.filename.as_ref().unwrap());
							path.set_extension("zip");
							let mut f = File::create(&path).expect(format!("Error opening file: {:?}", &path).as_str());
							f.write_all(&b).expect(format!("Error writing file: {:?}", &path).as_str());
							acc.push(addon)
						},
						Err(e) => eprintln!("Got an error while downloading: {}", e),
					}
				},
				Err(e) => eprintln!("Got a tokio::JoinError: {}", e),
			}
			acc
		})
		.await;

	let installed_addons = read_addons(&config.addon_json)?; 	

	let addons: Vec<Addon> = addons.into_iter()
		.flat_map(|mut addon| {
			addon.install(&config, &installed_addons)?;
			anyhow::Ok(addon)
		}).collect();

	let mut ids: Vec<u32> = installed_addons.clone().into_iter().map(|addon| addon.id).collect();

	let mut addons: Vec<Addon> = addons.into_iter()
		.map(|mut addon| {
			ids = addon.set_id(ids.clone());
			addon
		}).collect();

	for a in installed_addons {
		if !addons.contains(&a) {
			addons.push(a);
		}
	}

	write_addons(&addons, &config.addon_json)?;

  Ok(())
}

pub async fn update(addons: Vec<Addon>, config: &Config) -> anyhow::Result<()> {
  let client = Client::new();

  let addons_original = addons.clone();

	let updates = stream::iter(addons)
		.map(|addon| {
			let url = addon.latest_url();
			let client = client.clone();
			tokio::spawn(async move {
				let json = client.get(url)
				.header(CONTENT_TYPE, "application/json")
				.header(USER_AGENT, CHROME_USER_AGENT)
				.send()
				.await.unwrap()
				.json::<Value>()
				.await;
				(addon, json)
			})
		})
		.buffer_unordered(PARALLEL_REQUESTS);

	let acc: Vec<Addon> = Vec::new();
	let addons = updates
		.fold(acc, |mut acc, u| async {
			match u {
				Ok((mut addon, json)) => {
					match json {
						Ok(json) => {
							let update_needed = addon.set_version(&json);
              if update_needed {
                addon.set_download_url(&json);
                addon.set_name(&json);
                acc.push(addon);
              }
						},
						Err(e) => eprintln!("Got a reqwest::Error {}", e),		
					}
				},
				Err(e) => eprintln!("Got a tokio::JoinError: {}", e),
			}
			acc
		})
		.await;

  
  
  Ok(())
}

pub fn read_addons(path: &PathBuf) -> anyhow::Result<Vec<Addon>> {
	let s = fs::read_to_string(path)?;
	if s.is_empty() {
		return Ok(Vec::new())
	}
	let a: Vec<Addon> = serde_json::from_str(&s)?;
	Ok(a)
}

fn write_addons(addons: &Vec<Addon>, path: &PathBuf) -> anyhow::Result<()> {
	let s = serde_json::to_string_pretty(addons)?;
	fs::write(path, s)?;
	Ok(())
}





