#![allow(dead_code)]
#![allow(unused_variables)]
#![allow(unused_imports)]

use clap::Parser;
use regex::Regex;
use std::fs;
use tokio;

use crate::addon::{Addon, AddonKind};
use crate::config::{Config};
use crate::core::{install, update, read_addons};

mod addon;
mod config;
mod core;
mod unzip;

const CONFIG: &str = r"/home/mike/projects/lycan/test/lycan.cfg";

#[derive(Parser, Debug)]
#[clap(author, version, about, long_about = None)]
struct Cli {
	/// List of addons to install.
	#[clap(short, long, value_parser, multiple_values = true, group = "action")]
	install: Option<Vec<String>>,

	/// Update all installed addons.
	#[clap(short, long, group = "action")]
	update: bool,

	/// List of addon IDs to remove.
	#[clap(short, long, value_parser, multiple_values = true, group = "action")]
	remove: Option<Vec<u32>>
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
	let s = fs::read_to_string(CONFIG)?;
	let config: Config = serde_json::from_str(&s)?;

	let cli = Cli::parse();

	if let Some(urls) = cli.install {
		let mut addons: Vec<Addon> = Vec::new();
		for url in urls {
			if let Some(a) = addon_from_url(&url) {
				addons.push(a);
			}
		}
		install(addons, &config).await?;
	}


	if cli.update {
		let mut addons = read_addons(&config.addon_json)?;
		update(addons, &config).await?;
	}
	

	Ok(())
}

fn addon_from_url(url: &String) -> Option<Addon> {
	// implement lazy_static on the regex's here for speed
	let re = Regex::new(r#"^(?:https?://)?(?:www\.)?(?P<domain>.*)\.(?:com|org)/(?P<rest>.*)"#).unwrap();
	let caps = re.captures(url)?;
	let domain = caps.name("domain")?.as_str();
	let rest = caps.name("rest")?.as_str();
	match domain {
		"github" => {
			let re = Regex::new(r#"^(?P<project>.+?/.+?)(?:/|$)(?:tree/)?(?P<branch>.+)?"#).unwrap();
			let caps = re.captures(rest)?;
			let project = caps.name("project")?.as_str();
			Some(match caps.name("branch") {
				Some(m) => Addon::new(String::from(project), AddonKind::GithubRepo{branch: String::from(m.as_str())}),
				None => Addon::new(String::from(project), AddonKind::GithubRelease),
			})
		},
		"gitlab" => Some(Addon::new(String::from(rest), AddonKind::Gitlab)),
		"tukui" => {
			let re = Regex::new(r#"^(?P<kind>download|addons)\.php\?(?:ui|id)=(?P<project>.*)"#).unwrap();
			let caps = re.captures(rest)?;
			let project = caps.name("project")?.as_str();
			let kind = caps.name("kind")?.as_str();
			match kind {
				"download" => Some(Addon::new(String::from(project), AddonKind::TukuiMain)),
				"addons" => Some(Addon::new(String::from(project), AddonKind::TukuiAddon)),
				&_ => None,
			}
		},
		"wowinterface" => {
			let re = Regex::new(r#"^downloads/info(?P<project>\d*)-"#).unwrap();
			let caps = re.captures(rest)?;
			let project = caps.name("project")?.as_str();
			Some(Addon::new(String::from(project), AddonKind::WowInt))
		},
		&_ => None
	}
}
