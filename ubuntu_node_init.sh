#!/bin/bash
#******************************
#Author:zhb
#Time:2023-12-08
#Description:K8s Ubuntu Node Add
#******************************

# 加载初始化信息
source /tmp/info.sh

# 1）配置DNS
cat /etc/resolv.conf

# 2）配置阿里云源、安装工具
echo -e "\e[32m ----------2/10 配置阿里云源---------- \e[0m"

mv /etc/apt/sources.list /etc/apt/sources.list.bak
cat > /etc/apt/sources.list << EOF
deb http://mirrors.aliyun.com/ubuntu/ focal main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ focal-security main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ focal-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ focal-proposed main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ focal-backports main restricted universe multiverse
EOF

sudo apt-get update
apt -y install net-tools curl sysstat conntrack wget vim flannel nfs-common ntpdate autogen lrzsz lvm2 apt-transport-https ca-certificates ethtool

# 3）关防火墙、Selinux
echo -e "\e[32m ----------3/10 关闭防火墙、Selinux---------- \e[0m"
systemctl stop firewalld && systemctl disable firewalld
systemctl stop ufw && systemctl disable ufw
setenforce 0 && sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
getenforce
 
# 4）禁用swap分区
echo -e "\e[32m ----------4/10 禁用swap分区---------- \e[0m"
swapoff -a && free -h
sed -i /^[^#]*swap*/s/^/\#/g /etc/fstab
cat /etc/fstab

# 5）时间同步
echo -e "\e[32m ----------5/10 时间同步---------- \e[0m"
(crontab -l 2>/dev/null || true; echo "*/5 * * * * /usr/sbin/ntpdate ntp.aliyun.com") | crontab -
crontab -l

# 6）配置openfile数（根据机器配置来定）
echo -e "\e[32m ----------6/10 配置openfile数---------- \e[0m"
cat > /etc/security/limits.conf << EOF
* soft nofile 102400
* hard nofile 102400
EOF

cat > /etc/security/limits.d/20-nproc.conf << EOF
root soft nproc unlimited
root hard nproc unlimited
* soft nproc 102400
* hard nproc 102400
EOF

sed -i '/4096/d' /etc/security/limits.d/20-nproc.conf
ulimit -u -n

# 7）将桥接的IPv4流量传递到iptables的链、禁止ipv6的流量
echo -e "\e[32m ----------7/10 网络配置---------- \e[0m"
cat > /etc/sysctl.d/99-sysctl.conf <<EOF
vm.swappiness = 0
kernel.sysrq = 1
net.ipv4.neigh.default.gc_stale_time = 120
# see details in https://help.aliyun.com/knowledge_detail/39428.html
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.default.arp_announce = 2
net.ipv4.conf.lo.arp_announce = 2
net.ipv4.conf.all.arp_announce = 2
# see details in https://help.aliyun.com/knowledge_detail/41334.html
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 1024
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-arptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_local_reserved_ports = 30000-32767
vm.max_map_count = 262144
fs.inotify.max_user_instances = 524288
kernel.pid_max = 65535
EOF
 
#刷新生效
sysctl -p

modprobe overlay

sudo modprobe br_netfilter
lsmod | grep br_netfilter

# cat > /etc/sysconfig/modules/ipvs.modules <<EOF
# #!/bin/bash
# modprobe -- ip_vs
# modprobe -- ip_vs_rr
# modprobe -- ip_vs_wrr
# modprobe -- ip_vs_sh
# modprobe -- nf_conntrack_ipv4
# modprobe -- br_netfilter
# EOF

# chmod 755 /etc/sysconfig/modules/ipvs.modules && bash /etc/sysconfig/modules/ipvs.modules
# lsmod | grep -E  "ip_vs|nf_connt"

# 8）安装 Docker (尽量与当前集群中版本一致)
echo -e "\e[32m ----------8/10 安装Docker---------- \e[0m"
sudo apt -y install apt-transport-https ca-certificates curl gnupg-agent software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt update
# 这里安装的docker版本指定死了
sudo apt -y install docker-ce=5:$Docker_Version~3-0~ubuntu-focal docker-ce-cli=5:$Docker_Version~3-0~ubuntu-focal containerd.io

#更改默认存储目录、docker网段、harbor地址
mkdir -pv /beta/docker && mkdir -pv /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
   "bip": "192.168.0.1/24",
   "registry-mirrors": [
      "https://04rocj68.mirror.aliyuncs.com",
      "https://registry.docker-cn.com",
      "http://hub-mirror.c.163.com",
      "https://docker.mirrors.ustc.edu.cn"
   ],
   "log-driver": "json-file",
   "log-opts": {
      "max-size": "100m",
      "max-file": "3"
   },
   "insecure-registries": ["harbor.私有仓库地址xxxxx.com-1", "harbor.私有仓库地址xxxxx.com-2"],
   "data-root": "/beta/docker",
   "exec-opts": [
      "native.cgroupdriver=systemd"
   ]
}
EOF

systemctl daemon-reload
systemctl start docker && systemctl status docker && systemctl enable docker
docker info |grep "Docker Root Dir" && ifconfig docker0 |grep "192"

# 9）安装 kubelet kubeadm kubectl
echo -e "\e[32m ----------9/10 安装Node组件---------- \e[0m"
echo "deb https://mirrors.aliyun.com/kubernetes/apt kubernetes-xenial main" >> /etc/apt/sources.list
curl https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | sudo apt-key add
sudo apt update
apt install -y kubelet=$K8s_Version-00 kubeadm=$K8s_Version-00 kubectl=$K8s_Version-00 && systemctl enable kubelet

# 10）修改主机名(仅支持小写)
echo -e "\e[32m ----------10/10 修改主机名---------- \e[0m"
hostnamectl set-hostname $New_Hostname && hostname

# 11) 判断网卡名是否需要修改
Check_Result_Path=/opt/node_init_result.log

if [ `ip a |grep -w $Consul_Net_Interface | grep UP | wc -l` -ne 1 ];then
   echo -e "\e[33m !!!!网卡名不符合要求,需修改为eth0,请参考wiki修改!!!!"
   echo "Failed in K8s node initaliztion" > $Check_Result_Path
   exit 1
else 
   echo -e "\e[32m ----网卡名eth0符合要求---- \e[0m" && 
   ip a|grep eth0 |grep inet
   echo "Success in K8s node initaliztion" > $Check_Result_Path
fi

# 12) 判断网卡带宽是否为千兆
if [ `ethtool eth0|grep Speed|awk '{print $2}'` = "1000Mb/s" ];then
   echo -e "\e[33m !!!!网卡带宽不符合要求,需修改为千兆!!!!"
   echo "Failed in K8s node initaliztion【网卡带宽】" > $Check_Result_Path
   exit 1
else 
   echo -e "\e[32m ----网卡带宽符合要求---- \e[0m" && 
   ethtool eth0|grep Speed|awk '{print $2}'
   echo "Check Network Speed Success" > $Check_Result_Path
fi

#harbor认证
echo "PASSWORD密码" | docker login -u admin harbor.私有仓库地址xxxxx.com --password-stdin

#初始化镜像下载
docker pull harbor.私有仓库地址xxxxx.com/istio/proxyv2:1.15.2
docker tag harbor.私有仓库地址xxxxx.com/istio/proxyv2:1.15.2 docker.io/istio/proxyv2:1.15.2