#!/bin/bash

#------------# 填写新扩容节点信息--------------

# IP
export New_Node_IP=172.17.12.168

# 主机名
export New_Hostname=k8s-centos-172-17-12-168

# SSH端口
export SSH_Port=22

# 网卡要求
export Consul_Net_Interface=eth0

# 操作系统 | CentOS 或 Ubuntu
export OS=CentOS
export Docker_Version=20.10.12
export K8s_Version=1.21.5

#-----------------------------------------