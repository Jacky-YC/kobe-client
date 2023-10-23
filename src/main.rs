pub mod kobe_client;

use ::std::collections::HashMap;
use kobe_client::kobe_client::kobe_api_client::KobeApiClient;
use kobe_client::kobe_client::{GetResultRequest, Host, Inventory, RunAdhocRequest};
use std::error::Error;
use std::fs::File;
use std::io::Read;
use tonic::transport::Channel;

const REMOTE_IP: &str = "192.168.33.17";

const WORK_DIR: &str = "/Users/jacky/IdeaProjects/kobe-client";

fn read_private_key(path: &str) -> String {
    // Open the file
    let mut file = File::open(path).expect("Failed to open file");

    // Read the file contents into a string
    let mut contents = String::new();
    file.read_to_string(&mut contents)
        .expect("Failed to read file");

    let content = format!("{}", contents);

    content
}

fn read_script(path: String) -> String {
    // Open the file
    let mut file = File::open(path).expect("Failed to open file");

    // Read the file contents into a string
    let mut contents = String::new();
    file.read_to_string(&mut contents)
        .expect("Failed to read file");

    let content = format!("{}", contents);

    content
}

fn get_inventory() -> Inventory {
    let key = read_private_key("/Users/jacky/IdeaProjects/vagrant/infra/ubuntu1804/.vagrant/machines/ubuntu/virtualbox/private_key");

    let mut vars = HashMap::new();

    vars.insert("ansible_connection".to_string(), "ssh".to_string());
    vars.insert("deprecation_warnings".to_string(), "False".to_string());

    let host = Host {
        ip: REMOTE_IP.to_string(),
        name: "vagrant".to_string(),
        port: 22,
        user: "root".to_string(),
        password: "root".to_string(),
        private_key: "".to_string(),
        proxy_config: None,
        vars: vars,
    };

    Inventory {
        hosts: vec![host],
        groups: vec![],
        vars: HashMap::new(),
    }
}

fn build_adhoc_request() -> RunAdhocRequest {
    let inventory = get_inventory();

    // let path: String = WORK_DIR.to_string() + "/scripts/Linux_check_script.sh";
    let path: String = WORK_DIR.to_string() + "/scripts/Linux_check_script.sh";
    let sc: String = read_script(path);

    RunAdhocRequest {
        inventory: Some(inventory),
        pattern: "all".to_string(),
        module: "shell".to_string(),
        param: sc.to_string(),
    }
}

async fn build_kobe_client() -> Result<KobeApiClient<Channel>, tonic::transport::Error> {
    let kobe_server: String = format!("http://{}:{}", REMOTE_IP, 8080);
    KobeApiClient::connect(kobe_server).await
}

async fn send_adhoc_command(kc: &mut KobeApiClient<Channel>) -> Result<String, Box<dyn Error>> {
    let req = build_adhoc_request();
    let r = kc.run_adhoc(req).await?;
    let result: &kobe_client::kobe_client::Result = r.get_ref().result.as_ref().expect("No result");
    Ok(result.id.to_string())
}

async fn get_result_by_task_id(
    kc: &mut KobeApiClient<Channel>,
    task_id: &str,
) -> Result<kobe_client::kobe_client::Result, Box<dyn Error>> {
    let req = GetResultRequest {
        task_id: task_id.to_string(),
    };
    let binding = kc.get_result(req).await?;
    let r: &kobe_client::kobe_client::Result = binding.get_ref().item.as_ref().expect("No result");
    
    Ok(r.clone())
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Send exec script request.
    let mut kc: KobeApiClient<Channel> = build_kobe_client().await?;

    // let task_id = send_adhoc_command(&mut kc).await?;
    // println!("{} ", task_id);

    let result = get_result_by_task_id(&mut kc, "bf2bec78-bca2-4c42-bb47-c07124076c75").await?;
    println!("{} {} {}", result.success, result.message, result.content);

    Ok(())
}
