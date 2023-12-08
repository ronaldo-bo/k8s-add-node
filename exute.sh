#!/bin/bash
#******************************
#Author:zhb
#Time:2023-12-08
#Description:K8s Node Add
#******************************

# 信息脚本
Node_Info=info.sh
# 初始化日志检查
Node_Init_Result=/opt/node_init_result.log

# -----------展示新扩容节点的信息-----------
source ./info.sh

echo -e "\e[36m -----!新扩容节点信息如下,请确认是否正确!----- \e[0m"
echo 新节点-IP: $New_Node_IP
echo SSH端口: $SSH_Port
echo 主机名: $New_Hostname
echo 操作系统: $OS
echo Docker版本: $Docker_Version
echo K8s版本: $K8s_Version

# 操作系统类型区分
if [ $OS -eq CentOS ];then
        Node_Add_Script=centos_node_init.sh
else
        Node_Add_Script=ubuntu_node_init.sh
fi

# ---------------------------------------

echo -e "\e[32m ----------节点初始化前检查---------- \e[0m"
#用户确认
read -p "【${New_Node_IP}】请确认此节点是否为新扩容节点(yes or no): " first_check

if [ ${first_check} != yes ];then
        echo "No No No,不支持扩容!!" && exit 1
else
        echo "开始扩容"
fi

#二次检查
if [ `ssh -p  ${SSH_Port} ${New_Node_IP} ps -ef|grep docker |grep -v grep|wc -l` -eq 1 ];then
        echo "!!!!!!!!!!检查失败,Docker已运行,请检查新节点环境!!!!!!!!!!" && exit 1
else
        echo "---Docker检查通过---"
fi

if [ `ssh -p  ${SSH_Port} ${New_Node_IP} ps -ef|grep kubelet |grep -v grep|wc -l` -eq 1 ];then
        echo "!!!!!!!!!!检查失败,Kubelet已运行,请检查新节点环境!!!!!!!!!!" && exit 1
else
        echo "---Kubelet检查通过---"
fi

#1.开始初始化
scp -P $SSH_Port $Node_Info root@$New_Node_IP:/tmp/$Node_Info
scp -P $SSH_Port $Node_Add_Script root@$New_Node_IP:/tmp/$Node_Add_Script
ssh -p $SSH_Port root@$New_Node_IP bash /tmp/$Node_Add_Script

if [ `ssh -p ${SSH_Port} ${New_Node_IP} cat $Node_Init_Result | grep Success | wc -l` -ne 1 ];then
	echo "节点初始化失败,请检查!" && exit 1
else
	echo "节点初始化成功，下边开始加入集群"
fi

#2.初始化完毕后，开始从master节点扩容至集群
#hosts新加
echo "${New_Node_IP} ${New_Hostname}" >> /etc/hosts
scp -P $SSH_Port /etc/hosts root@${New_Node_IP}:/etc/hosts

#hosts备份
for i in `kubectl get node -owide|awk '{print $6}'|grep -v INTERNAL-IP`;do ssh -p ${SSH_Port} root@$i cp /etc/hosts{,-$(date +%F)};done
#hosts分发
for i in `kubectl get node -owide|awk '{print $6}'|grep -v INTERNAL-IP`;do scp -P ${SSH_Port} /etc/hosts root@$i:/etc/hosts;done


#生成加入集群的命令 这里应该优化下？
echo -e "\e[32m --------!!!请将下边这条命令，放到【新扩容node】运行!!!---------- \e[0m"
kubeadm token create --print-join-command --ttl 0

# 等待上边这条命令在新节点运行完毕
echo -e "\e[32m --------!!!上边这条命令在【新节点】运行完毕后，开始下边的扩容操作---------- \e[0m"
echo "等待上边执行完5秒......."
sleep 5

#Master节点验证
echo -e "\e[32m --------【在新节点加入集群后】可以参考下变的步骤命令验证----------\e[0m"

cat > check_result.log <<EOF
# 以下命令可以直接在[master]节点运行
## 禁止调度
kubectl cordon ${New_Hostname}

## 打标签
kubectl label node ${New_Hostname} beta.istio=istio 
kubectl label node ${New_Hostname} beta.nginx=nginx 
kubectl label node ${New_Hostname} beta.dns=dns

## 验证新节点运行情况
kubectl get node -owide
kubectl get pod -A -o wide |grep ${New_Hostname}
EOF

cat check_result.log && rm -f check_result.log

# 还要多拷贝一步cni flannel 网络插件? 此步骤可能要优化步骤
ssh -p $SSH_Port root@$New_Node_IP mkdir -pv /opt/cni/bin
scp -r -P ${SSH_Port} /opt/cni/bin/* root@${New_Node_IP}:/opt/cni/bin

echo -e "\e[32m -------------------扩容结束------------------- \e[0m"