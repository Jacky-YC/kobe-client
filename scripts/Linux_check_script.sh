#!/bin/bash
# Author: Yinlin Li(yinlin@seal.io)
# Last Change: 2023-09-12

# Usage message
usage () {
    echo "####################################"
    echo "USAGE: $0"
    echo "  [ -os ] Output os info only"
    echo "  [ -debug ] Output more debug info"
    echo "  [ -h | -help ] Usage message"
    echo "####################################"
}

# Process checklist
process_checklist=(
    # Middleware
    ## Nginx
    "nginx"
    ## Tomcat
    "tomcat"
    ## Redis
    "redis-server"
    ## XC
    ### TongWeb
    "tongweb"
    ### TongRDS
    "pcenter"
    "pmemdb"
    ### TongHttpServer
    "httpserver"
    ### TongHTP
    "htp_namesvr"
    "htp_broker_server"
    ### BES
    "bes"
    # Database
    ## MySQL
    "mysqld"
    ## Oracle
    "tnslsnr"
    ## DB2
    "db2sysc"
    ## XC
    ### SequoiaDB
    "sdbcm"
    ### DM
    "dmserver"
)


# Output OS info
get_server_info() {
    server_hostname=$(hostname -s)
    default_interface=$(ip route | awk '/default/ {print $5}')
    ipv4_address=$(ip addr show dev $default_interface | awk '/inet / {print $2}' | cut -d/ -f1)
    ipv6_address=$(ip addr show dev $default_interface | awk '/inet6 / {print $2}' | cut -d/ -f1)
    if [[ -z $ipv6_address ]]; then
        ip_array='["'$ipv4_address'"]'
    else
        ip_array='["'$ipv4_address'", "'$ipv6_address'"]'
    fi
    mac_address=$(cat /sys/class/net/$default_interface/address)
    server_os=$(grep -w "NAME" /etc/os-release | awk -F "=" '{print $NF}')
    if [[ $server_os == *"Kylin Linux Advanced Server"* ]]; then
        server_os_version=$(nkvers 2>/dev/null | grep -w "/")
    elif [[ $server_os == *"UnionTech OS Server"* ]]; then
        server_os_version=$(grep -E 'MajorVersion|MinorVersion|OsBuild' /etc/os-version | awk -F'=' '{printf $2"."}' | sed 's/\.$//')
    else
        server_os_version=$(grep -w "VERSION" /etc/os-release | awk -F "=" '{print $NF}' | tr -d '"')
    fi
    server_kernel=$(uname -r)
    if [[ $only_output_os_info ]]; then
        echo '{"hostname": "'$server_hostname'", "ip_array": '$ip_array', "mac_address": "'$mac_address'", "os": '$server_os', "os_version": "'$server_os_version'", "kernel": "'$server_kernel'"}'
    fi
}

# Judge output content
output_judge() {
    if [[ -z $port ]] || [[ -z $version ]]; then
        if [ "$debug" = true  ]; then
            echo -e '[DEBUG] {"hostname": "'$server_hostname'", "ip_array": '$ip_array', "mac_address": "'$mac_address'", "result": "process '$process' port or version check failure"}'
        fi
    else
        output $type $software_type $name $version $port $components
    fi
}

# Check and ouptput processes info
process_check()
{
    output() {
        local type=$1
        local software_type=$2
        local name=$3
        local version=$4
        local port=$5
        local components=$6
        echo '{"hostname": "'$server_hostname'", "ip_array": '$ip_array', "mac_address": "'$mac_address'", "os": '$server_os', "os_version": "'$server_os_version'", "kernel": "'$server_kernel'", "type": "'$type'", "'$software_type'": "'$name'","state": "running", "version": "'$version'", "port": ['$port'], "in_com": '$components'}'
    }
    found_process=false
    for process in "${process_checklist[@]}"; do
        if ps aux | grep "$process" | grep -v grep >/dev/null; then
            found_process=true
            # Processing for different processes
            case $process in
                "nginx")
                    software_type=middleware_type
                    name=Nginx
                    type=middleware
                    port=$(sudo netstat -tlnp | grep "$process" | awk '{print $4}' | awk -F ":" '{print $NF}' | tr '\n' ',' | sed 's/,$//')
                    version=$(sudo $(readlink -f /proc/$(ps -ef | grep nginx | grep master| grep -v grep | awk '{print $2}')/exe | xargs dirname)/nginx -v 2>&1 | awk -F '/' '{print $2}')              
                    components='{"components":[{"name":"'$process'","state":"running","port":['$port'],"version":"'$version'"}]}'
                    output_judge
                    ;;
                "tomcat")
                    software_type=middleware_type
                    name=Tomcat
                    type=middleware
                    port=$(sudo netstat -tlnp | grep java | grep $(ps aux | grep tomcat | grep "org.apache.catalina.startup.Bootstrap" | grep -v grep | awk '{print $2}') | grep -v "127.0.0.1" | awk '{print $4}' | awk -F ":::" '{print $NF}' | tr '\n' ',' | sed 's/,$//')
                    catalina_home=$(sudo ps -Ao cmd | grep tomcat | grep -oP "(?<=-Dcatalina.home=)[^[:space:]]+")
                    version=$(sudo $catalina_home/bin/catalina.sh version 2>/dev/null | grep "Server version" | awk '{print $NF}' | cut -d '/' -f 2)
                    components='{"components":[{"name":"'$process'","state":"running","port":['$port'],"version":"'$version'"}]}'
                    output_judge
                    ;;
                "redis-server")
                    software_type=middleware_type
                    name=Redis
                    type=middleware
                    port=$(sudo netstat -tlnp | grep "$process" | grep -v tcp6 | awk '{print $4}' | awk -F ":" '{print $NF}' | tr '\n' ',' | sed 's/,$//')
                    version=$(sudo $(readlink -f /proc/$(ps -ef | grep redis-server | grep -v grep | awk '{print $2}')/exe | xargs dirname)/redis-cli -v | awk '{print $2}')
                    components='{"components":[{"name":"'$process'","state":"running","port":['$port'],"version":"'$version'"}]}'
                    output_judge
                    ;;
                "tongweb")
                    software_type=middleware_type
                    name=TongWeb
                    type=middleware
                    port=$(sudo netstat -tlnp | grep java | grep $(ps aux | grep "tongweb.pid" | grep -v grep | awk '{print $2}') | awk '{print $4}' | awk -F ":" '{print $NF}' | tr '\n' ',' | sed 's/,$//')
                    tongweb_dir=$(sudo ps -Ao cmd | grep tongweb | grep -oP "(?<=-Duser.dir=)[^[:space:]]+")
                    version=$(sudo $tongweb_dir/version.sh 2>/dev/null | grep -oP 'TongWeb \K\d+(\.\d+)+')
                    components='{"components":[{"name":"'$process'","state":"running","port":['$port'],"version":"'$version'"}]}'
                    output_judge
                    ;;
                 "pcenter")
                    software_type=middleware_type
                    name=TongRDS
                    type=middleware
                    port=$(sudo netstat -tlnp | grep java | grep $(ps aux | grep pcenter | grep java | grep -v grep | awk '{print $2}') | awk '{print $4}' | awk -F ":" '{print $NF}' | tr '\n' ',' | sed 's/,$//')
                    tongrds_dir=$(sudo ps -Ao cmd | grep pcenter | grep -oP "(?<=-Dserver.home=)[^[:space:]]+")
                    version=$(sudo "$tongrds_dir"/bin/Version.sh 2>/dev/null | grep Version | awk '{print $2}')
                    components='{"components":[{"name":"'$process'","state":"running","port":['$port'],"version":"'$version'"}]}'
                    if ps aux | grep "pmemdb" | grep -v grep >/dev/null; then
                        pcenter_port=$(sudo netstat -tlnp | grep java | grep $(ps aux | grep pcenter | grep java | grep -v grep | awk '{print $2}') | awk '{print $4}' | awk -F ":" '{print $NF}' | tr '\n' ',' | sed 's/,$//')
                        pmemdb_port=$(sudo netstat -tlnp | grep java | grep $(ps aux | grep pmemdb | grep java | grep -v grep | awk '{print $2}') | awk '{print $4}' | awk -F ":" '{print $NF}' | tr '\n' ',' | sed 's/,$//')
                        port+=,$pmemdb_port
                        tongrds_dir=$(sudo ps -Ao cmd | grep pmemdb | grep -oP "(?<=-Dserver.home=)[^[:space:]]+")
                        pmemdb_version=$(sudo "$tongrds_dir"/bin/Version.sh 2>/dev/null | grep Version | awk '{print $2}')
                        components='{"components":[{"name":"'$process'","state":"running","port":['$pcenter_port'],"version":"'$version'"},{"name":"pmemdb","state":"running","port":"'$pmemdb_port'","version":"'$pmemdb_version'"}]}'
                    fi
                    output_judge
                    ;;
                 "pmemdb")
                    if pgrep -x "pcenter" > /dev/null; then
                        :
                    else                 
                        software_type=middleware_type
                        name=TongRDS
                        type=middleware
                        port=$(sudo netstat -tlnp | grep java | grep $(ps aux | grep pmemdb | grep java | grep -v grep | awk '{print $2}') | awk '{print $4}' | awk -F ":" '{print $NF}' | tr '\n' ',' | sed 's/,$//')
                        tongrds_dir=$(sudo ps -Ao cmd | grep pmemdb | grep -oP "(?<=-Dserver.home=)[^[:space:]]+")
                        version=$(sudo "$tongrds_dir"/bin/Version.sh 2>/dev/null | grep Version | awk '{print $2}')
                        components='{"components":[{"name":"'$process'","state":"running","port":['$port'],"version":"'$version'"}]}'
                        output_judge
                    fi
                    ;;
                "httpserver")
                    software_type=middleware_type
                    name=TongHttpServer
                    type=middleware
                    httpserver_bin=$(ps -Ao cmd | grep httpserver | grep "httpserver: master process" | grep -v grep | awk '{print $4}')
                    port=$(sudo netstat -tlnp | grep "$process" | awk '{print $4}' | awk -F ":" '{print $NF}' | tr '\n' ',' | sed 's/,$//')
                    version=$($httpserver_bin -v 2>&1>/dev/null | grep -oP 'TongHttpServer/\K\d+(\.\d+)+')
                    components='{"components":[{"name":"'$process'","state":"running","port":['$port'],"version":"'$version'"}]}'
                    output_judge
                    ;;
                "htp_namesvr")
                    software_type=middleware_type
                    name=TongHTP
                    type=middleware
                    port=$(sudo netstat -tlnp | grep "$process" | awk '{print $4}' | awk -F ":" '{print $NF}' | tr '\n' ',' | sed 's/,$//')
                    htp_bin=$(ps -Ao cmd | grep htp_namesvr | grep -v grep)
                    version=$($htp_bin -v 2>/dev/null | awk '{print $2}')
                    components='{"components":[{"name":"'$process'","state":"running","port":['$port'],"version":"'$version'"}]}'
                    if ps aux | grep "htp_broker_server" | grep -v grep >/dev/null; then
                        namesvr_port=$(sudo netstat -tlnp | grep "$process" | awk '{print $4}' | awk -F ":" '{print $NF}' | tr '\n' ',' | sed 's/,$//')
                        broker_port=$(sudo netstat -tlnp | grep broker_server | awk '{print $4}' | awk -F ":" '{print $NF}' | tr '\n' ',' | sed 's/,$//')
                        port+=,$broker_port
                        htp_bin=$(ps -Ao cmd | grep htp_broker_server | grep -v grep | awk '{print $1}')
                        broker_version=$($htp_bin -v 2>/dev/null | awk '{print $4}')
                        components='{"components":[{"name":"namesvr","state":"running","port":['$namesvr_port'],"version":"'$version'"},{"name":"broker","state":"running","port":"'$broker_port'","version":"'$broker_version'"}]}'
                    fi
                    output_judge
                    ;;
                "htp_broker_server")
                    if pgrep -x "htp_namesvr" > /dev/null; then
                        :
                    else                    
                        software_type=middleware_type
                        name=TongHTP
                        type=middleware
                        htp_bin=$(ps -Ao cmd | grep htp_broker_server | grep -v grep | awk '{print $1}')
                        port=$(sudo netstat -tlnp | grep broker_server | awk '{print $4}' | awk -F ":" '{print $NF}' | tr '\n' ',' | sed 's/,$//')
                        version=$($htp_bin -v 2>/dev/null | awk '{print $4}')
                        components='{"components":[{"name":"'$process'","state":"running","port":['$port'],"version":"'$version'"}]}'
                        output_judge
                    fi
                    ;;
                 "bes")
                    software_type=middleware_type
                    name=BES
                    type=middleware
                    port=$(sudo netstat -tlnp | grep java | grep $(ps aux | grep bes | grep -v grep | awk '{print $2}') | awk '{print $4}' | awk -F ":" '{print $NF}' | tr '\n' ',' | sed 's/,$//')
                    bes_dir=$(sudo ps -Ao cmd | grep -oE '\-Dbes\.home=[^ ]+' | awk -F'=' '{print $2}')
                    version=$(sudo cat $bes_dir/logs/server.log 2>/dev/null | grep "main|Version" | awk -F ": " '{print $2}' | awk -F "|" '{print $1}')
                    components='{"components":[{"name":"'$process'","state":"running","port":['$port'],"version":"'$version'"}]}'
                    output_judge
                    ;;
                "mysqld")
                    if pgrep -x "sdbcm" > /dev/null; then
                        :
                    else
                        software_type=database_type
                        name=MySQL
                        type=database
                        port=$(sudo netstat -tlnp | grep "$process" | awk '{print $4}' | awk -F ":" '{print $NF}' | tr '\n' ',' | sed 's/,$//')
                        version=$(mysql -V | awk '{print $3}')
                        components='{"components":[{"name":"'$process'","state":"running","port":['$port'],"version":"'$version'"}]}'
                        output_judge
                    fi
                    ;;
                "tnslsnr")
                    software_type=database_type
                    name=Oracle
                    type=database
                    port=$(sudo netstat -tlnp | grep "$process" | awk '{print $4}' | awk -F ":" '{print $NF}' | tr '\n' ',' | sed 's/,$//')
                    version=$(sudo su - oracle -c "sqlplus -v" | awk -F " " '{print $3}' | tr -d '[:space:]')
                    components='{"components":[{"name":"TNS_Listener","state":"running","port":['$port'],"version":"'$version'"}]}'
                    output_judge
                    ;;
                "db2sysc")
                    software_type=database_type
                    name=DB2
                    type=database
                    port=()
                    port=$(sudo netstat -tlnp | grep "$process" | awk '{print $4}' | awk -F ":" '{print $NF}' | tr '\n' ',' | sed 's/,$//')
                    instances=$(ps -ef | grep db2sysc | grep -v grep | awk '{print $1}')
                    for instance in $instances; do
                        version=$(sudo su - $instance -c db2level | grep "Informational tokens" | awk -F '"' '{print $2}' | cut -d " " -f 2)
                        instance_pid=$(ps -ef | grep db2sysc | grep "$instance" | grep -v grep | awk '{print $2}')
                        instance_port=$(sudo netstat -tlnp | grep "$process" | grep "$instance_pid" | awk '{print $4}' | awk -F ":" '{print $NF}' | tr '\n' ',' | sed 's/,$//')
                        component+=('{"name":"'$instance'","state":"running","port":['$instance_port'],"version":"'$version'"}')
                    done
                    components=$(IFS=,; echo "${component[*]}")
                    components='{"components":['$components']}'
                    output_judge
                    ;;
                "sdbcm")
                    software_type=database_type
                    name=SequoiaDB
                    type=database
                    port=$(sudo netstat -tlnp | grep -E "$process|mysqld|postgres" | awk '{print $4}' | awk -F ":" '{print $NF}' | tr '\n' ',' | sed 's/,$//')
                    if command -v sequoiadb >/dev/null; then
                        version=$(sequoiadb --version 2>/dev/null | grep "SequoiaDB version" | awk '{print $NF}')
                    else
                        sequoiadb_dir=$(grep "INSTALL_DIR" /etc/default/sequoiadb |awk -F"=" '{print $2}')
                        version=$(sudo $sequoiadb_dir/bin/sequoiadb --version 2>/dev/null | grep "SequoiaDB version" | awk '{print $NF}')
                        sequoiadb_port=$(sudo netstat -tlnp | grep -E "$process" | awk '{print $4}' | awk -F ":" '{print $NF}' | tr '\n' ',' | sed 's/,$//')
                    fi
                    if ps aux | grep "mysqld" | grep -v grep > /dev/null; then
                        mysql_port=$(sudo netstat -tlnp | grep "mysqld" | awk '{print $4}' | awk -F ":" '{print $NF}' | tr '\n' ',' | sed 's/,$//')
                        sequoiasql_mysql_dir=$(grep "INSTALL_DIR" /etc/default/sequoiasql-mysql |awk -F"=" '{print $2}')
                        mysql_version=$(sudo $sequoiasql_mysql_dir/bin/mysql -V 2>/dev/null | awk '{print $5}' | tr -d ',')
                        components='{"components":[{"name":"sdbcm","state":"running","port":['$sequoiadb_port'],"version":"'$version'"},{"name":"sequoiasql-mysql","state":"running","port":['$mysql_port'],"version":"'$mysql_version'"}]}'
                        if ps aux | grep "postgres" | grep -v grep > /dev/null; then
                            postgresql_port=$(sudo netstat -tlnp | grep "postgres" | awk '{print $4}' | awk -F ":" '{print $NF}' | tr '\n' ',' | sed 's/,$//')
                            sequoiasql_postgresql_dir=$(grep "INSTALL_DIR" /etc/default/sequoiasql-postgresql |awk -F"=" '{print $2}')
                            postgresql_version=$(sudo $sequoiasql_postgresql_dir/bin/postgres -V 2>/dev/null | grep "postgres" | awk '{print $NF}')
                            components='{"components":[{"name":"sdbcm","state":"running","port":['$sequoiadb_port'],"version":"'$version'"},{"name":"sequoiasql-mysql","state":"running","port":['$mysql_port'],"version":"'$mysql_version'"},{"name":"sequoiasql-postgresql","state":"running","port":['$postgresql_port'],"version":"'$postgresql_version'"}]}'
                        fi
                    elif ps aux | grep "postgres" | grep -v grep > /dev/null; then
                        postgresql_port=$(sudo netstat -tlnp | grep "postgres" | awk '{print $4}' | awk -F ":" '{print $NF}' | tr '\n' ',' | sed 's/,$//')
                        sequoiasql_postgresql_dir=$(grep "INSTALL_DIR" /etc/default/sequoiasql-postgresql |awk -F"=" '{print $2}')
                        postgresql_version=$(sudo $sequoiasql_postgresql_dir/bin/postgres -V 2>/dev/null | grep "postgres" | awk '{print $NF}')
                        components='{"components":[{"name":"sdbcm","state":"running","port":['$sequoiadb_port'],"version":"'$version'"},{"name":"sequoiasql-postgresql","state":"running","port":['$postgresql_port'],"version":"'$postgresql_version'"}]}'
                    else
                        components='{"components":[{"name":"sdbcm","state":"running","port":['$sequoiadb_port'],"version":"'$version'"}]}'
                    fi
                    output_judge
                    ;;
                "dmserver")
                    software_type=database_type
                    name=DM
                    type=database
                    port=$(sudo netstat -tlnp | grep "$process" | awk '{print $4}' | awk -F ":" '{print $NF}' | tr '\n' ',' | sed 's/,$//')
                    version=$(sudo /home/dmdba/dmdbms/tool/version.sh)
                    components='{"components":[{"name":"'$process'","state":"running","port":['$port'],"version":"'$version'"}]}'
                    output_judge
                    ;;
            esac
        fi
    done
    if [[ "$found_process" = false && "$debug" = true ]]; then
        echo -e '{"hostname": "'$server_hostname'", "ip_array": '$ip_array', "mac_address": "'$mac_address'", "result": "all not found"}'
        return 255
    fi
}

# Call the function to check for installation
main()
{
    while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
            -os)
            only_output_os_info=true
            shift
            ;;
            -debug)
            debug=true
            shift
            ;;
            -h|--help)
            help=true
            shift
            ;;
            *)
            usage
            exit 1
            ;;
        esac
    done

    if [[ $help ]]; then
        usage
        exit 0
    fi

    if [[ $only_output_os_info ]]; then
        get_server_info
    else
        get_server_info
        process_check    
    fi
}


main "$@"