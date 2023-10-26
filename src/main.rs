use kobe_client::kobe_api::client::kobe_api_client::KobeApiClient;
use tonic::transport::Channel;
use async_std::task;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Send exec script request.
    let mut kc: KobeApiClient<Channel> = kobe_client::build_kobe_client().await?;

    let task_id = kobe_client::send_adhoc_command(&mut kc).await?;
    
    // let task_id = kobe_client::send_adhoc_command(&mut kc).await?;
    // println!("{} ", task_id);

    // let task_id = kobe_client::send_playbook_command(&mut kc).await?;
    println!("{} ", task_id);

    let result = task::block_on(kobe_client::get_result_by_task_id(&mut kc, &task_id))?;
    println!("{} {} {}", result.success, result.message, result.content);

    Ok(())
}
