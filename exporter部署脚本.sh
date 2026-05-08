#!/bin/bash

echo "===注意对rabbitmq的操作要在此部署前单独处理，见下方注释==="
echo "===注意，监控安装包请放在/root目录下==="

deploy_ip=""
mysql_pass=""

# 询问是否为本地部署
read -rp "# 是否为本地部署？(y/n): " is_local

# 转为小写便于判断
is_local=$(echo "$is_local" | tr '[:upper:]' '[:lower:]')

case "$is_local" in
    y|yes)
        echo "检测到本地部署，IP 地址设为 127.0.0.1"
        deploy_ip="127.0.0.1"
        ;;
    n|no)
        read -rp "# 请输入部署服务器 IP 地址: " deploy_ip
        firewall-cmd --add-port={9999,10000,10001,10002,10003,15692}/tcp --permanent
        firewall-cmd --reload
        ;;
    *)
        echo "无效输入，默认视为非本地部署。"
        read -rp "# 请输入部署服务器 IP 地址: " deploy_ip
        firewall-cmd --add-port={9999,10000,10001,10002,10003,15692}/tcp --permanent
        firewall-cmd --reload
        ;;
esac



echo "===部署process-exporter==="

tar -zxf /root/process-exporter-0.8.7.linux-amd64.tar.gz 
mkdir -p /etc/exporter/process_exporter
touch /etc/exporter/process_exporter/config.yaml
cp ./process-exporter-0.8.7.linux-amd64/process-exporter /usr/local/bin
tee  /etc/exporter/process_exporter/config.yaml <<EOF
process_names:
  - name: "finance-latest.jar"
    cmdline:
    - '^java.*finance-latest.jar$'
    
  - name: "php-queue-worker"
    cmdline:
    - 'php.*think queue:work --daemon$'
EOF
tee /etc/systemd/system/process-exporter.service <<EOF
[Unit]
Description=Process Exporter
Documentation=https://github.com/ncabatoff/process-exporter
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/local/bin/process-exporter -config.path /etc/exporter/process_exporter/config.yaml -web.listen-address ${deploy_ip}:9999

# 重启策略
Restart=always
RestartSec=10
StartLimitInterval=60
StartLimitBurst=5


# 日志设置
StandardOutput=journal
StandardError=journal


[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl start process-exporter
systemctl enable process-exporter
echo "===检测process-exporter服务是否正常==="
systemctl is-active process-exporter





echo "===部署node-exporter==="
tar -zxf /root/node_exporter-1.9.1.linux-amd64.tar.gz
cp ./node_exporter-1.9.1.linux-amd64/node_exporter /usr/local/bin
tee /etc/systemd/system/node-exporter.service <<EOF
[Unit]
Description=node Exporter
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/local/bin/node_exporter --web.listen-address ${deploy_ip}:10000

# 重启策略
Restart=always
RestartSec=10
StartLimitInterval=60
StartLimitBurst=5

# 日志设置
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl start node-exporter
systemctl enable node-exporter
echo "===检测node-exporter服务是否正常==="
systemctl is-active node-exporter




# rabbitmq-plugins enable rabbitmq_prometheus
# rabbitmq-plugins enable rabbitmq_management

# # 根据部署类型生成配置
# if [[ "$is_local" =~ ^(y|yes)$ ]]; then
#     # 本地部署：仅开启详细指标，监听默认（127.0.0.1）
#     tee /etc/rabbitmq/rabbitmq.conf <<EOF
# prometheus.return_per_object_metrics = true
# EOF
# else
#     # 非本地部署：允许外部访问 Prometheus 指标端口
#     tee /etc/rabbitmq/rabbitmq.conf <<EOF
# prometheus.return_per_object_metrics = true
# prometheus.tcp.port = 15692
# prometheus.tcp.ip = ${deploy_ip}
# EOF
# fi

# systemctl restart rabbitmq-server
# echo "===检测rabbitmq-server服务是否正常==="
# systemctl is-active rabbitmq-server


echo "===部署blackbox-exporter==="
tar -zxf /root/blackbox_exporter-0.27.0.linux-amd64.tar.gz 
mkdir -p /etc/exporter/black_exporter
cp ./blackbox_exporter-0.27.0.linux-amd64/blackbox.yml /etc/exporter/black_exporter
cp ./blackbox_exporter-0.27.0.linux-amd64/blackbox_exporter /usr/local/bin
tee /etc/exporter/black_exporter/blackbox.yml <<EOF
modules:
  http_rabbitmq_api:  
    prober: http
    timeout: 15s
    http:
      valid_status_codes: [200]
      method: GET
      headers:
        Authorization: "Basic Z3Vlc3Q6Z3Vlc3Q="
        #为 HTTP 探针（prober）在向目标 URL 发起请求时，自动添加一个 HTTP 请求头 Authorization，使用 Basic 认证方式提供用户名和密码。
      fail_if_body_not_matches_regexp: ['"status":"ok"']  
  qywx_api: 
    prober: http
    timeout: 15s
    http:
      valid_status_codes: [403]
      method: GET
EOF
tee /etc/systemd/system/blackbox-exporter.service <<EOF
[Unit]
Description=blackbox_exporter
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root

ExecStart=/usr/local/bin/blackbox_exporter --web.listen-address ${deploy_ip}:10003 --config.file=/etc/exporter/black_exporter/blackbox.yml

# 重启策略
Restart=always
RestartSec=10
StartLimitInterval=60
StartLimitBurst=5

# 日志设置
StandardOutput=journal
StandardError=journal


[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl start blackbox-exporter
systemctl enable blackbox-exporter
echo "===检测blackbox-exporter服务是否正常==="
systemctl is-active blackbox-exporter




tar -zxf /root/mysqld_exporter-0.17.2.linux-amd64.tar.gz 
mkdir  /etc/exporter/mysqld_exporter
touch /etc/exporter/mysqld_exporter/.my.cnf
cp ./mysqld_exporter-0.17.2.linux-amd64/mysqld_exporter /usr/local/bin
echo "===部署mysqld-exporter==="
read -rp "# 请输入mysql密码：" mysql_pass
tee /etc/exporter/mysqld_exporter/.my.cnf <<EOF
[client]
user = root
password = ${mysql_pass}
host = 127.0.0.1
port = 3306
EOF
tee /etc/systemd/system/mysqld-exporter.service <<EOF
[Unit]
Description=mysqld Exporter
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/local/bin/mysqld_exporter --web.listen-address ${deploy_ip}:10001 --config.my-cnf=/etc/exporter/mysqld_exporter/.my.cnf

# 重启策略
Restart=always
RestartSec=10
StartLimitInterval=60
StartLimitBurst=5


# 日志设置
StandardOutput=journal
StandardError=journal


[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl start mysqld-exporter
systemctl enable mysqld-exporter
echo "===检测mysqld-exporter服务是否正常==="
systemctl is-active mysqld-exporter






tar -zxf /root/redis_exporter-v1.77.0.linux-amd64.tar.gz
cp ./redis_exporter-v1.77.0.linux-amd64/redis_exporter /usr/local/bin
tee /etc/systemd/system/redis-exporter.service <<EOF
[Unit]
Description=redis Exporter
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/local/bin/redis_exporter --web.listen-address ${deploy_ip}:10002

# 重启策略
Restart=always
RestartSec=10
StartLimitInterval=60
StartLimitBurst=5

# 日志设置
StandardOutput=journal
StandardError=journal


[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl start redis-exporter
systemctl enable redis-exporter
echo "===检测redis-exporter服务是否正常==="
systemctl is-active redis-exporter






