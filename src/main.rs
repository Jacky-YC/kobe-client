pub mod kobe_client;

use ::std::collections::HashMap;
use kobe_client::kobe_client::kobe_api_client::KobeApiClient;
use kobe_client::kobe_client::{Host, Inventory, RunAdhocRequest, RunAdhocResult};
use std::fmt::format;
use std::fs::File;
use std::io::Read;
use std::{string, result};

const REMOTE_IP: &str = "192.168.33.17";

const WORK_DIR: &str = "/Users/jacky/IdeaProjects/kobe-client";

fn read_script(path: String) -> String {
    // Open the file
    let mut file = File::open(path).expect("Failed to open file");

    // Read the file contents into a string
    let mut contents = String::new();
    file.read_to_string(&mut contents)
        .expect("Failed to read file");

    let content = format!("executable=shell {}", contents);

    content
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {

    let host = Host {
        ip: REMOTE_IP.to_string(),
        name: "vagrant".to_string(),
        port: 22,
        user: "vagrant".to_string(),
        password: "".to_string(),
        private_key: "".to_string(),
        proxy_config: None,
        vars: HashMap::new(),
    };

    let inventory = Inventory {
        hosts: vec![host],
        groups: vec![],
        vars: HashMap::new(),
    };

    let path: String = WORK_DIR.to_string() + "/scripts/Linux_check_script.sh";
    let sc: String = read_script(path);

    let req = RunAdhocRequest {
        inventory: Some(inventory),
        pattern: "default_host".to_string(),
        module: "shell".to_string(),
        param: sc.to_string(),
    };

    let kobeServer = format!("http://{}:{}", REMOTE_IP, 8080);

    let mut kc = KobeApiClient::connect(kobeServer).await?;

    let r = kc.run_adhoc(req).await?;

    let result: &kobe_client::kobe_client::Result = r.get_ref().result.as_ref().expect("No result");

    println!("{}", result.id);
    
    
    Ok(())
}

