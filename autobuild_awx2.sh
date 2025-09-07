#!/bin/sh
# setup ansible AWX environment in ubuntu box (multi tenant version)

##############
# Variables
##############

AWXVERSION=21.3.0
AWX_MAJOR_VERSION=${AWXVERSION%%.*}

: ${AWXHOST:=localhost}
: ${ORG:=my-org}
: ${NODES:="node01 node02 node03"}

if [ $AWX_MAJOR_VERSION -ge 18 ];then
  AWXTASK=tools_awx_1
else
  AWXTASK=awx_task
fi

echo "$AWXVERSION ($AWX_MAJOR_VERSION) : ${AWXTASK}"

# set debug prompt
PS4=`printf "[\033[36;40;1m${0##*/}\033[0m]$ "`
# remove localhost entry from dockerhost's /etc/hosts (ubuntu)
sed -i 's/\(^127.0.1.1.*$\)/# \1/' /etc/hosts

##############
# subroutines
##############

installpackage(){
# ___           _        _ _   ____                            ____         __ _
#|_ _|_ __  ___| |_ __ _| | | |  _ \ _ __ ___ _ __ ___  __ _  / ___|  ___  / _| |___      ____ _ _ __ ___  ___
# | || '_ \/ __| __/ _` | | | | |_) | '__/ _ \ '__/ _ \/ _` | \___ \ / _ \| |_| __\ \ /\ / / _` | '__/ _ \/ __|
# | || | | \__ \ || (_| | | | |  __/| | |  __/ | |  __/ (_| |  ___) | (_) |  _| |_ \ V  V / (_| | | |  __/\__ \
#|___|_| |_|___/\__\__,_|_|_| |_|   |_|  \___|_|  \___|\__, | |____/ \___/|_|  \__| \_/\_/ \__,_|_|  \___||___/
#                                                         |_|
# install prerequisite packages

sudo apt update
sudo apt-get -y -qq -o=Dpkg::Use-Pty=0 install figlet
figlet -w 150 01. Install Prereq Softwares

set -x

if sudo systemctl > /dev/null ;then
  :
else
  : "[Error] systemd disabled. "
  : "Update wsl.conf"
  printf "### enable systemd for docker $(date +%Y%m%d) ###\n[boot]\nsystemd=true\n" | sudo tee -a /etc/wsl.conf
  : "[Action] issue wsl --shutdown  in Powershell console"
fi

sudo apt -y -qq install git python3-pip python3-virtualenv docker-compose expect nmon

if sudo systemctl is-enabled sshd ; then
  :
else
  sudo apt -y -qq install openssh-server openssh-client
fi

# install docker service when the system dont installed docker service

if sudo systemctl is-enabled docker ; then
:
else
  sudo apt-get -y install ca-certificates curl gnupg lsb-release &&\
  sudo mkdir -m 0755 -p /etc/apt/keyrings &&\
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg |\
     sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg &&\
  echo \
  "deb [arch=$(dpkg --print-architecture) \
   signed-by=/etc/apt/keyrings/docker.gpg] \
   https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) stable" | \
   sudo tee /etc/apt/sources.list.d/docker.list > /dev/null &&\
  sudo apt update
  sudo apt-get -y install docker-ce docker-ce-cli \
            containerd.io docker-buildx-plugin \
            docker-compose-plugin
fi
## install buildx (for killercoda)
#sudo apt-get -y install docker-buildx-plugin

# add user to docker group
if [ ! -r /var/run/docker.sock ];then
  sudo usermod -a -G docker $(whoami)
  : "[Error] you ($(whoami)) can not access /var/run/docker.socket. so I add you docker group in /etc/group"
  : "[Action] Please exit session and re-login and rerun ${0##*/}"
  : "[Error] ($(whoami)) ユーザーは /var/run/docker.socket ファイルにアクセスできないようだったのでdockerグループに追加しました "
  : "[Action] ログインしなおして、改めて ${0##*/} スクリプトを実行してください"
return 1
fi

#sudo pip install pip --upgrade  || return 1
#sudo pip install setuptools_scm || return 1
#sudo pip install setuptools --upgrade
# sudo pip install 'ansible==2.10'  最新の ubuntu で ansible 2.10 を導入できなくなってしまったので古い AWx (15とか) を入れられなくなる。。 (2024/8/13)
pip install 'ansible' --break-system-packages           || return 1
pip install setuptools_scm --break-system-packages      || return 1
pip install setuptools --upgrade --break-system-packages|| return 1
#pip install docker-compose  || return 1 
ansible --version

sudo systemctl is-active docker || { sleep 10 ; sudo systemctl restart docker || return 1 ;}
set +x
}

installawx(){
# ___           _        _ _      _
#|_ _|_ __  ___| |_ __ _| | |    / \__      ____  __
# | || '_ \/ __| __/ _` | | |   / _ \ \ /\ / /\ \/ /
# | || | | \__ \ || (_| | | |  / ___ \ V  V /  >  <
#|___|_| |_|___/\__\__,_|_|_| /_/   \_\_/\_/  /_/\_\
#
figlet -w 150 02. Install Awx ${AWXVERSION}
set -x
git clone -b ${AWXVERSION} https://github.com/ansible/awx.git ~/awx

### To use Local inventory ###
# perl -i.bak -ple 's/#project_data_dir=/project_data_dir=/' inventory
# diff --color -u inventory.bak inventory

if [ $AWX_MAJOR_VERSION -ge 18 ];then
  cd ~/awx/  || return 1
  if [ $AWX_MAJOR_VERSION -le 19 ];then # awx18, awx19
    : tools/ansible/roles/dockerfile/templates/Dockerfile.j2
    : RUN sed -i -e 's@^mirrorlist@#mirrorlist@g;s@^#baseurl=http://mirror@baseurl=http://vault@g' /etc/yum.repos.d/CentOS-*repo
    sed -i "/# Install build/iRUN sed -i -e 's@^mirrorlist@#mirrorlist@g;s@^#baseurl=http://mirror@baseurl=http://vault@g' /etc/yum.repos.d/CentOS-*repo" tools/ansible/roles/dockerfile/templates/Dockerfile.j2
    sed -i "/# Install runtime/iRUN sed -i -e 's@^mirrorlist@#mirrorlist@g;s@^#baseurl=http://mirror@baseurl=http://vault@g' /etc/yum.repos.d/CentOS-*repo" tools/ansible/roles/dockerfile/templates/Dockerfile.j2
    : requirements/requirements_git.txt
    : "git+git              -> git+https"
    : "ansible-runner devel -> 1.4.9"
    sed -i 's/git+git:/git+https:/;s/\(ansible-runner.*\)@devel/\1@1.4.9/'  requirements/requirements_git.txt
    : docker-compose -f tools/docker-compose/_sources/docker-compose.yml $(COMPOSE_UP_OPTS) up
    sed -i 's/$(COMPOSE_UP_OPTS) up/up $(COMPOSE_UP_OPTS)/' Makefile
  elif [ ${AWXVERSION} = "21.3.0" ];then
  ## build docker image (if version equal 21.3.0, pull prebuild images)
    sudo docker pull mirrorcity/awx213:1.2
    sudo docker tag  mirrorcity/awx213:1.2 ghcr.io/ansible/awx_devel:HEAD
    sudo docker rmi  mirrorcity/awx213:1.2
  else
    LC_ALL=C.utf8 make SHELL=/bin/bash PYTHON=python3 docker-compose-build  || return 1
  fi

  # fix inventory file for fix build error 20250402
  sed -i '1s@/usr/bin/env python3@/usr/bin/python3@' ~/awx/tools/docker-compose/inventory
  LC_ALL=C.utf8 make SHELL=/bin/bash PYTHON=python3 COMPOSE_UP_OPTS=-d docker-compose || return 1

  if [ ${AWXVERSION} = "21.3.0" ];then
  ## **experimental** do "npm run start" instead of "npm run build"
      sudo docker exec tools_awx_1 tar xf /awxui_21.3.tar.gz || return 1
      sudo docker exec --user root tools_awx_1 yum -y --quiet install lsof iputils || return 1

cat << EOF > ~/awx/startnpm.sh
#!/bin/sh
export TERM=dumb
env NODE_OPTIONS=--max-old-space-size=3076 npm --prefix awx/ui --loglevel warn start | cat &
echo wait to open listen port 8013...
until lsof -i -n -P | grep :8013 ; do printf . ; sleep 1 ; done
echo "open! [8013]"
sleep 1
EOF

      chmod 755 ~/awx/startnpm.sh
      docker exec --user root tools_awx_1 /awx_devel/startnpm.sh || return 1
  ## end **experimental**
  else
  ## build npm user interface
  ## change memory usage limitation during build (for killercoda)
    sudo docker exec tools_awx_1 make clean-ui ui-devel || return 1
  fi

else
  # awx version <= 17
  cd ~/awx/installer  || return 1
  if [ -r ~/patch.awx15 ] ;then
    patch -p2 < ~/patch.awx15
  fi
  # for awx17
  perl -i.bak -ple 's/^# admin_password=/admin_password=/' inventory

  ansible-playbook -i inventory install.yml  || return 1
  docker-compose -f ~/.awx/awxcompose/docker-compose.yml restart
fi

set +x
}

extractassets(){
# _____      _                  _     _                 _                      _
#| ____|_  _| |_ _ __ __ _  ___| |_  | | ___   ___ __ _| |   __ _ ___ ___  ___| |_ ___
#|  _| \ \/ / __| '__/ _` |/ __| __| | |/ _ \ / __/ _` | |  / _` / __/ __|/ _ \ __/ __|
#| |___ >  <| |_| | | (_| | (__| |_  | | (_) | (_| (_| | | | (_| \__ \__ \  __/ |_\__ \
#|_____/_/\_\\__|_|  \__,_|\___|\__| |_|\___/ \___\__,_|_|  \__,_|___/___/\___|\__|___/
#
figlet -w 150 03. Extract local assets
set -x
cd ~/
gzip -cd my_assets*.tar.gz | tar tvf -
gzip -cd my_assets*.tar.gz | tar xf -
[ -r ~/.ansible.cfg ] || cp -fv ~/awx-asset.git/ansible.cfg ~/.ansible.cfg

perl -i -ple 's@^inventory.*$@inventory = ~/awx-asset.git/'${ORG%-org}'-inventory@' ~/.ansible.cfg

### Copy Asset to Local inventory ###
#mkdir -p /var/lib/awx/projects/
#mv -iv ~/awx-asset.git /var/lib/awx/projects/
#ln -sf /var/lib/awx/projects/awx-asset.git ~/
set +x
}

buildendpoint(){
# ____        _ _     _   _____           _             _       _
#| __ ) _   _(_) | __| | | ____|_ __   __| |_ __   ___ (_)_ __ | |_ ___
#|  _ \| | | | | |/ _` | |  _| | '_ \ / _` | '_ \ / _ \| | '_ \| __/ __|
#| |_) | |_| | | | (_| | | |___| | | | (_| | |_) | (_) | | | | | |_\__ \
#|____/ \__,_|_|_|\__,_| |_____|_| |_|\__,_| .__/ \___/|_|_| |_|\__|___/
#                                          |_|

figlet -w 150 04. Build Endpoints
set -x
mkdir -p -m700 ~/.ssh/
cd ~/endpoint-docker/

# if not exist, create ssh key.
if [ -r ~/endpoint-docker/${ORG%-org}-ssh-keypair ] ; then
  :
else
  ssh-keygen -t ed25519 -N "" -f ${ORG%-org}-ssh-keypair
  cp -iv ${ORG%-org}-ssh-keypair ~/.ssh/
fi

# symbroc link for include endpoint container (for Dockerfile)
ln -sf ${ORG%-org}-ssh-keypair.pub ssh-keypair.pub

# create docker-compose setup file
cp -fv ~/endpoint-docker/docker-compose.tmpl ~/endpoint-docker/${ORG%-org}-docker-compose.yaml

## set listenable ports list between 8081..8999
set $(perl -mIO::Socket -e 'map { my $socket = IO::Socket::INET->new(Proto=>"tcp",LocalAddr=>"localhost:$_") and print $_."\n";}(8081..8999)' | head -$(echo ${NODES}|wc -w))

## create docker-compose.yaml entry for every nodes
for node in ${NODES}
do

PORT=$1
shift

cat << EOF >> ~/endpoint-docker/${ORG%-org}-docker-compose.yaml
  ${node}:
    image: local/centos:stream9
    container_name: ${node}
    hostname: ${node}
    ports:
      - "${PORT}:80"
    privileged: true
    command: /sbin/init
EOF

done

## build image and create container
docker-compose -f ~/endpoint-docker/${ORG%-org}-docker-compose.yaml build || return 1
docker-compose -f ~/endpoint-docker/${ORG%-org}-docker-compose.yaml up -d

set +x
}

connectawxnet(){
set -x
#  ____                            _        _                   _   _      _                      _
# / ___|___  _ __  _ __   ___  ___| |_     / \__      ____  __ | \ | | ___| |___      _____  _ __| | __
#| |   / _ \| '_ \| '_ \ / _ \/ __| __|   / _ \ \ /\ / /\ \/ / |  \| |/ _ \ __\ \ /\ / / _ \| '__| |/ /
#| |__| (_) | | | | | | |  __/ (__| |_   / ___ \ V  V /  >  <  | |\  |  __/ |_ \ V  V / (_) | |  |   <
# \____\___/|_| |_|_| |_|\___|\___|\__| /_/   \_\_/\_/  /_/\_\ |_| \_|\___|\__| \_/\_/ \___/|_|  |_|\_\
#
AWXNET=$(docker inspect --format '{{range $k,$v := .NetworkSettings.Networks}}{{println $k}}{{end}}' ${AWXTASK} 2> /dev/null)

if [ x"${AWXNET:-null}" = x"null" ] ;then
  echo "There is no awx networks. (do nothing)"
else
  for node in ${NODES}
  do
    docker network disconnect endpoint-docker_default ${node}
    docker network connect ${AWXNET} ${node}
  done
fi

for node in ${NODES}
do
docker inspect --format '{{range $k,$v := .NetworkSettings.Networks}}{{println $k $v.IPAddress}}{{end}}' ${node}
done

set +x
}

disconnectawxnet(){
set -x
# ____  _                                 _        _                   _   _      _                      _
#|  _ \(_)___  ___  _ __  _ __   ___  ___| |_     / \__      ____  __ | \ | | ___| |___      _____  _ __| | __
#| | | | / __|/ _ \| '_ \| '_ \ / _ \/ __| __|   / _ \ \ /\ / /\ \/ / |  \| |/ _ \ __\ \ /\ / / _ \| '__| |/ /
#| |_| | \__ \ (_) | | | | | | |  __/ (__| |_   / ___ \ V  V /  >  <  | |\  |  __/ |_ \ V  V / (_) | |  |   <
#|____/|_|___/\___/|_| |_|_| |_|\___|\___|\__| /_/   \_\_/\_/  /_/\_\ |_| \_|\___|\__| \_/\_/ \___/|_|  |_|\_\
#

AWXNET=$(docker inspect --format '{{range $k,$v := .NetworkSettings.Networks}}{{println $k}}{{end}}' ${AWXTASK} 2> /dev/null)

if [ x"${AWXNET:=null}" = x"null" ];then
  echo "There is no awx networks. (do nothing)"
else
  for node in ${NODES}
  do
    docker network disconnect ${AWXNET} ${node}
    docker network connect endpoint-docker_default ${node}
  done
fi

for node in ${NODES}
do
docker inspect --format '{{range $k,$v := .NetworkSettings.Networks}}{{println $k $v.IPAddress}}{{end}}' ${node}
done

set +x
}

setupdockerhost(){
# ____       _                     _            _             _               _
#/ ___|  ___| |_ _   _ _ __     __| | ___   ___| | _____ _ __| |__   ___  ___| |_
#\___ \ / _ \ __| | | | '_ \   / _` |/ _ \ / __| |/ / _ \ '__| '_ \ / _ \/ __| __|
# ___) |  __/ |_| |_| | |_) | | (_| | (_) | (__|   <  __/ |  | | | | (_) \__ \ |_
#|____/ \___|\__|\__,_| .__/   \__,_|\___/ \___|_|\_\___|_|  |_| |_|\___/|___/\__|
#                     |_|
figlet -w 150 05. Setup dockerhost for endpoint
set -x

# setup ssh/config file for local ansible execution
cat << EOF >> ~/.ssh/config
Host ${NODES}
  user epuser
  IdentityFile ~/.ssh/${ORG%-org}-ssh-keypair
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

EOF

# (re)create local ansible inventory
cp -f ~/awx-asset.git/inventory.tmpl ~/awx-asset.git/${ORG%-org}-inventory
sed -i "s/ssh-keypair/${ORG%-org}-ssh-keypair/" ~/awx-asset.git/${ORG%-org}-inventory

# insert host-ip relation to local inventory and /etc/hosts
for node in ${NODES}
do
   ip=$(docker inspect --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${node})

  if grep ${node} ~/awx-asset.git/${ORG%-org}-inventory > /dev/null ; then
    sed -i "s/^${node}.*$/${node} ansible_host=${ip}/" ~/awx-asset.git/${ORG%-org}-inventory
  else
    printf "${node} ansible_host=${ip}\n" | tee -a ~/awx-asset.git/${ORG%-org}-inventory
  fi

  if grep ${node} /etc/hosts > /dev/null ; then
    sudo sed -i "s/^.*${node}[ ]*$/${ip} ${node}/" /etc/hosts
  else
    printf "%-15s %s\n" ${ip} ${node} | sudo tee -a /etc/hosts
  fi

  while ! nc -vz $node 22 ; do sleep 1 ; done
  ssh ${node} uname -n
done

# update github and inventory
updateinventory "setup endpoint info"

set +x
}

updateinventory(){
set -x
# _   _           _       _         ___                      _
#| | | |_ __   __| | __ _| |_ ___  |_ _|_ ____   _____ _ __ | |_ ___  _ __ _   _
#| | | | '_ \ / _` |/ _` | __/ _ \  | || '_ \ \ / / _ \ '_ \| __/ _ \| '__| | | |
#| |_| | |_) | (_| | (_| | ||  __/  | || | | \ V /  __/ | | | || (_) | |  | |_| |
# \___/| .__/ \__,_|\__,_|\__\___| |___|_| |_|\_/ \___|_| |_|\__\___/|_|   \__, |
#      |_|                                                                 |___/

COMMENT="${1:=misc update}"

# (1) update git repository (if exist)
if [ -d ~/awx-asset.git/.git/ ] ;then
  cd ~/awx-asset.git
  git add ~/awx-asset.git/${ORG%-org}-inventory
  git commit -m "${COMMENT}"
  git push origin master
fi

# (2) update inventory source (if exist)
if [ -r ~/awx-cli ];then
  if ~/awx-cli project get ${ORG%-org}-project 2>/dev/null ;then
    ~/awx-cli project update ${ORG%-org}-project || return 1
    sleep 10
    ~/awx-cli inventory_source update ${ORG%-org}-inventory-source
  fi
fi
set +x
}

setupgit(){
figlet -w 150 06. Setup Local Git environment
set -x
# ____       _                 _                    _    ____ _ _                     _                                      _
#/ ___|  ___| |_ _   _ _ __   | |    ___   ___ __ _| |  / ___(_) |_    ___ _ ____   _(_)_ __ ___  _ __  _ __ ___   ___ _ __ | |_
#\___ \ / _ \ __| | | | '_ \  | |   / _ \ / __/ _` | | | |  _| | __|  / _ \ '_ \ \ / / | '__/ _ \| '_ \| '_ ` _ \ / _ \ '_ \| __|
# ___) |  __/ |_| |_| | |_) | | |__| (_) | (_| (_| | | | |_| | | |_  |  __/ | | \ V /| | | | (_) | | | | | | | | |  __/ | | | |_
#|____/ \___|\__|\__,_| .__/  |_____\___/ \___\__,_|_|  \____|_|\__|  \___|_| |_|\_/ |_|_|  \___/|_| |_|_| |_| |_|\___|_| |_|\__|
#                     |_|

# setup git user and bare repository
sudo useradd git
# unlock account
sudo usermod -p '*' git

sudo install -d ~git -o git -g git -m 755
sudo install -d ~git/awx-asset.git -o git -g git -m 755
sudo su - git -c 'cd awx-asset.git; git init --bare --shared'

if [ -r  ~/.ssh/githost_key ] ; then
:
else
sudo su - git -c 'ssh-keygen -N "" -t ed25519 -f ~/.ssh/githost_key; cp ~/.ssh/githost_key.pub ~/.ssh/authorized_keys'
sudo cat  ~git/.ssh/githost_key > ~/.ssh/githost_key
chmod 600  ~/.ssh/githost_key

cat << EOF >> ~/.ssh/config
Host git
  user git
  Hostname localhost
  IdentityFile  ~/.ssh/githost_key
  UserKnownHostsFile /dev/null
  StrictHostKeyChecking no

EOF
fi

# create local git repository
cd ~/awx-asset.git
git init ~/awx-asset.git/
git config --global user.email "root@example.com"
git config --global user.name "Charlie Root"
git config --global --add safe.directory /root/awx-asset.git
git remote add origin ssh://git/home/git/awx-asset.git
git add *
git commit -m "initial commit"
git push origin master

# update git host to tools_awx_1's/ hosts
AWXNET=$(sudo docker inspect --format '{{range $k,$v := .NetworkSettings.Networks}}{{println $k}}{{end}}' ${AWXTASK} 2> /dev/null)

if [ ${AWXNET:-null} = null ];then
  :
else
  HOSTIP=$(sudo docker network inspect ${AWXNET} --format '{{range.IPAM.Config}}{{.Gateway}}{{end}}')
  sudo docker exec --user root ${AWXTASK} sh -c "echo ${HOSTIP} $(uname -n) >> /etc/hosts"  || return 1
  sudo docker exec --user root ${AWXTASK} cat /etc/hosts
#  sudo docker exec --user root ${AWXTASK} yum -y --quiet install lsof iputils procps-ng || return 1
  sudo docker exec --user root ${AWXTASK} ping -c 3 $(uname -n)
fi
set +x
}

setupjumphost(){
figlet -w 150 09. Setup Jumphost
set -x
# ____       _                     _                       _               _
#/ ___|  ___| |_ _   _ _ __       | |_   _ _ __ ___  _ __ | |__   ___  ___| |_
#\___ \ / _ \ __| | | | '_ \   _  | | | | | '_ ` _ \| '_ \| '_ \ / _ \/ __| __|
# ___) |  __/ |_| |_| | |_) | | |_| | |_| | | | | | | |_) | | | | (_) \__ \ |_
#|____/ \___|\__|\__,_| .__/   \___/ \__,_|_| |_| |_| .__/|_| |_|\___/|___/\__|
#                     |_|                           |_|

# disconnect awx network and connect original network
disconnectawxnet
# update /etc/hosts and invenory
setupdockerhost
set -x

## create new container into endpoint-docker_default
docker run -d --privileged -p 10022:22 --network=endpoint-docker_default -h jumphost --name jumphost local/centos:stream9 /sbin/init 2>/dev/null

# setup jumphost user
docker exec --user root jumphost useradd jhuser
# unlock account
docker exec --user root jumphost usermod -p '*' jhuser
docker exec --user root jumphost install -d /home/jhuser -o jhuser -g jhuser -m 755

# create ssh secret key
if docker exec --user root jumphost test -r  /home/jhuser/.ssh/jumphost_key ; then
 :
else
docker exec --user root jumphost su - jhuser -c 'ssh-keygen -N "" -t ed25519 -f ~/.ssh/jumphost_key; cp ~/.ssh/jumphost_key.pub ~/.ssh/authorized_keys'

# copy ssh secret key to dockerhost's directory
docker exec --user root jumphost cat /home/jhuser/.ssh/jumphost_key > ~/.ssh/jumphost_key
chmod 600  ~/.ssh/jumphost_key

# setup ssh/config file
cat << EOF >> ~/.ssh/config
Host jumphost
  User jhuser
  IdentityFile  ~/.ssh/jumphost_key
  UserKnownHostsFile /dev/null
  StrictHostKeyChecking no

EOF
fi

## get jumphost's ip address
ip1=$(docker inspect -f '{{ $network := index .NetworkSettings.Networks "endpoint-docker_default" }}{{ $network.IPAddress }}' jumphost)

## get network info to connect awx network
AWXNET=$(docker inspect --format '{{range $k,$v := .NetworkSettings.Networks}}{{println $k}}{{end}}' ${AWXTASK} 2> /dev/null)
if [ ${AWXNET:-null} = null ] ;then
  ip2=$(hostname -i)
  ansible_port="ansible_port=10022"
else
  docker network connect ${AWXNET} jumphost
  ip2=$(docker inspect -f '{{.NetworkSettings.Networks.'${AWXNET}'.IPAddress}}' jumphost)
  ansible_port=""
fi

## add jumphost address to dockerhost's /etc/hosts
if grep ${node} /etc/hosts > /dev/null ; then
  sudo sed -i "s/^.*${node}[ ]*$/${ip1} jumphost/" /etc/hosts
else
  printf "%-15s %s\n" ${ip1} jumphost | sudo tee -a /etc/hosts
fi

# update inventory and commit
if [ -d ~/awx-asset.git/.git/ ] ;then

  # update inventory (do nothing for tutorial)
  if grep -c ansible_ssh_common_args  ~/awx-asset.git/${ORG%-org}-inventory > /dev/null; then
  :  sed -i 's!ansible_ssh_common_args.*!ansible_ssh_common_args=-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $JH_SSH_KEY -W %h:%p  $JH_USER@$JH_HOST -p ${JH_PORT:=22}"!' ~/awx-asset.git/${ORG%-org}-inventory
  else
  :  sed -i '/web:vars/aansible_ssh_common_args=-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $JH_SSH_KEY -W %h:%p  $JH_USER@$JH_HOST -p ${JH_PORT:=22}"' ~/awx-asset.git/${ORG%-org}-inventory
  fi

  ## add inventory
  if grep jumphost ~/awx-asset.git/${ORG%-org}-inventory > /dev/null ; then
    sed -i "s/^jumphost.*$/jumphost ansible_host=${ip2} ansible_user=epuser ${ansible_port}/" ~/awx-asset.git/${ORG%-org}-inventory
  else
    sed -i "1ijumphost ansible_host=${ip2} ansible_user=epuser ${ansible_port}" ~/awx-asset.git/${ORG%-org}-inventory
  fi
fi

# update github and inventory, inventory-source
updateinventory "setup jumphost"

# update awx info (add credential type for jumphost)
if [ -r ~/awx-cli ];then
  # create new credential_type for store jumphost's information
  if ~/awx-cli credential_type get ssh_jumphost_cred_type 2>/dev/null ; then
    :
  else
    ~/awx-cli credential_type create --name ssh_jumphost_cred_type --kind cloud \
     --inputs '{"fields":[
              {"id":"hostname","type":"string","label":"Jumphost Hostname (hostname:$JH_HOST)"},
              {"id":"username","type":"string","label":"Username to Login Jumphost (username:$JH_USER)"},
              {"id":"ssh_key","type":"string","label":"SSH private key for Jumphost (ssh_key:$JH_SSH_KEY)","format":"ssh_private_key","secret":true,"multiline":true},
              {"id":"port","type":"string","label":"SSH Port to Login Jumphost (port:$JH_PORT)"}],
           "required":["username","hostname","ssh_key"]}' \
     --injectors '{
           "env":{"JH_HOST":"{{  hostname  }}","JH_PORT":"{{  port  }}","JH_SSH_KEY":"{{tower.filename.ssh_key}}","JH_USER":"{{  username  }}"},
           "file":{"template.ssh_key":"{{ssh_key}}\n\n"}}'  || return 1
   fi

  # create new ssh_jumphost_cred_type for jumphst  (do nothing for tutorial)
  if false ; then
#  if [ -r ~/.ssh/jumphost_key ] ; then
    if [ ${AWXHOST} = localhost ] ;then
      JUMPHOST=jumphost
      PORT=
    else
      JUMPHOST=$(uname -n)
      PORT=10022
    fi

    if ~/awx-cli credential get ${ORG%-org}-jumphost 2>/dev/null ; then
       ~/awx-cli credential modify ${ORG%-org}-jumphost --organization "${ORG}" \
                                  --inputs '{"hostname": "'${JUMPHOST}'","port" : "'${PORT}'","username": "jhuser" , "ssh_key": "@~/.ssh/jumphost_key"}'
    else
       ~/awx-cli credential create --credential_type  "ssh_jumphost_cred_type" --name ${ORG%-org}-jumphost --organization "${ORG}" \
                                  --inputs '{"hostname": "'${JUMPHOST}'","port" : "'${PORT}'","username": "jhuser" , "ssh_key": "@~/.ssh/jumphost_key"}'
    fi
  fi
fi

set +x
}

setupjumphost_orig(){
# ____       _                     _                       _               _      __          _     __
#/ ___|  ___| |_ _   _ _ __       | |_   _ _ __ ___  _ __ | |__   ___  ___| |_   / /___  _ __(_) __ \ \
#\___ \ / _ \ __| | | | '_ \   _  | | | | | '_ ` _ \| '_ \| '_ \ / _ \/ __| __| | |/ _ \| '__| |/ _` | |
# ___) |  __/ |_| |_| | |_) | | |_| | |_| | | | | | | |_) | | | | (_) \__ \ |_  | | (_) | |  | | (_| | |
#|____/ \___|\__|\__,_| .__/   \___/ \__,_|_| |_| |_| .__/|_| |_|\___/|___/\__| | |\___/|_|  |_|\__, | |
#                     |_|                           |_|                          \_\            |___/_/

figlet -w 150 09. Setup Jumphost
set -x

### setup jumphost when there is no ${AWXTASK} in same box ###

# setup jumphost user
sudo useradd jhuser
# unlock account
sudo usermod -p '*' jhuser
sudo install -d ~jhuser -o jhuser -g jhuser -m 755

if [ -r  ~/.ssh/jumphost_key ] ; then
:
else
sudo su - jhuser -c 'ssh-keygen -N "" -t ed25519 -f ~/.ssh/jumphost_key; cp ~/.ssh/jumphost_key.pub ~/.ssh/authorized_keys'
sudo cat ~jhuser/.ssh/jumphost_key > ~/.ssh/jumphost_key
chmod 600  ~/.ssh/jumphost_key

# setup ssh/config file
cat << EOF >> ~/.ssh/config
Match User jhuser
  IdentityFile  ~/.ssh/jumphost_key
  UserKnownHostsFile /dev/null
  StrictHostKeyChecking no

EOF
fi

# update inventory
sed -i '/web:vars/a___UNCOMMENT_IF_YOU_USE_JUMPHOST___ansible_ssh_common_args=-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $JH_SSH_KEY -W %h:%p  $JH_USER@$JH_HOST -p ${JH_PORT:=22}"' ~/awx-asset.git/${ORG%-org}-inventory

# commit file (if already setup git)
if [ -d ~/awx-asset.git/.git/ ] ;then
  cd ~/awx-asset.git
  git add ~/awx-asset.git/${ORG%-org}-inventory
  git commit -m "Update Jumphost"
  git push origin master
fi

# remove localhost entry from dockerhost's /etc/hosts
sed -i 's/\(^127.0.1.1.*$\)/# \1/' /etc/hosts

set +x
}

setupawxcli(){
figlet -w 150 07. Setup Awx Cli command
# ____       _                    _                    ____ _ _                                                 _
#/ ___|  ___| |_ _   _ _ __      / \__      ____  __  / ___| (_)   ___ ___  _ __ ___  _ __ ___   __ _ _ __   __| |
#\___ \ / _ \ __| | | | '_ \    / _ \ \ /\ / /\ \/ / | |   | | |  / __/ _ \| '_ ` _ \| '_ ` _ \ / _` | '_ \ / _` |
# ___) |  __/ |_| |_| | |_) |  / ___ \ V  V /  >  <  | |___| | | | (_| (_) | | | | | | | | | | | (_| | | | | (_| |
#|____/ \___|\__|\__,_| .__/  /_/   \_\_/\_/  /_/\_\  \____|_|_|  \___\___/|_| |_| |_|_| |_| |_|\__,_|_| |_|\__,_|
#                     |_|

if [ $(docker ps | grep -c ${AWXTASK}) -ge 1 ];then
  while TASKS=$(docker exec ${AWXTASK}  awx-manage showmigrations | grep '^ \[ ' | wc -l) ; [ ${TASKS:-0} -gt 0 ] ;
  do
    echo "[  ] waiting for migrate: ${TASKS} tasks left;"
    sleep 10 ;
  done ;
  echo "[OK] awx migrate tasks done"
fi

if [ $AWX_MAJOR_VERSION -ge 18 ];then

  cat << EOF > ~/chadmpasswd.sh
#!/usr/bin/expect -f
spawn docker exec -ti tools_awx_1 awx-manage changepassword admin
expect "Password:"
send "password\r"
expect "Password (again):"
send "password\r"
interact
EOF

  chmod 755 ~/chadmpasswd.sh
  ~/chadmpasswd.sh

  URL=https://${AWXHOST}:8043/
else
  URL=http://${AWXHOST}/
fi

set -x
# sudo pip3 install https://releases.ansible.com/ansible-tower/cli/ansible-tower-cli-latest.tar.gz
sudo pip3 install awxkit

sh -c 'printf "awx --conf.insecure --conf.host '${URL}' --conf.username admin --conf.password password -f human \"\$@\"\n" > ~/awx-cli'
chmod 755 ~/awx-cli

set +x

until ~/awx-cli ping -f human > /dev/null ;
  do echo "[  ] waiting for login"
sleep 1
done

echo "[OK] awx connect success"

~/awx-cli config
}

setupsampleconfig(){
figlet -w 150 08.Import Sample config
set -x
# ___                            _     ____                        _                         __ _
#|_ _|_ __ ___  _ __   ___  _ __| |_  / ___|  __ _ _ __ ___  _ __ | | ___    ___ ___  _ __  / _(_) __ _
# | || '_ ` _ \| '_ \ / _ \| '__| __| \___ \ / _` | '_ ` _ \| '_ \| |/ _ \  / __/ _ \| '_ \| |_| |/ _` |
# | || | | | | | |_) | (_) | |  | |_   ___) | (_| | | | | | | |_) | |  __/ | (_| (_) | | | |  _| | (_| |
#|___|_| |_| |_| .__/ \___/|_|   \__| |____/ \__,_|_| |_| |_| .__/|_|\___|  \___\___/|_| |_|_| |_|\__, |
#              |_|                                          |_|                                   |___/

cd ~/
if [ -r ~/.ssh/jumphost_key ];then
~/awx-cli credential_type create --name ssh_jumphost_cred_type --kind cloud \
   --inputs '{"fields":[
              {"id":"hostname","type":"string","label":"Jumphost Hostname (hostname:$JH_HOST)"},
              {"id":"username","type":"string","label":"Username to Login Jumphost (username:$JH_USER)"},
              {"id":"ssh_key","type":"string","label":"SSH private key for Jumphost (ssh_key:$JH_SSH_KEY)","format":"ssh_private_key","secret":true,"multiline":true},
              {"id":"port","type":"string","label":"SSH Port to Login Jumphost (port:$JH_PORT)"}],
           "required":["username","hostname","ssh_key"]}' \
   --injectors '{
           "env":{"JH_HOST":"{{  hostname  }}","JH_PORT":"{{  port  }}","JH_SSH_KEY":"{{tower.filename.ssh_key}}","JH_USER":"{{  username  }}"},
           "file":{"template.ssh_key":"{{ssh_key}}\n\n"}}'
fi

if [ -f ~/awx-asset.git/${ORG%-org}-inventory ];then
~/awx-cli organizations create --name "${ORG}" || return 1
~/awx-cli user create --username ${ORG}-admin --email ${ORG}-admin@${ORG}.example.com --password password
~/awx-cli user grant --organization ${ORG} --role member ${ORG}-admin
~/awx-cli user grant --organization ${ORG} --role admin ${ORG}-admin

~/awx-cli credential create --credential_type "Source Control" --name ${ORG%-org}-githost --organization "${ORG}"\
                            --inputs '{"username": "git", "ssh_key_data": "@~/.ssh/githost_key"}'
~/awx-cli projects create --name ${ORG%-org}-project --organization ${ORG} --scm_type git\
                          --scm_url ssh://git@$(uname -n)/home/git/awx-asset.git --credential ${ORG%-org}-githost
~/awx-cli inventory create --name ${ORG%-org}-inventory --organization ${ORG}
~/awx-cli inventory_source create --name ${ORG%-org}-inventory-source --inventory ${ORG%-org}-inventory\
                                  --source scm --overwrite true --overwrite_vars true \
                                  --source_project ${ORG%-org}-project --source_path ${ORG%-org}-inventory
~/awx-cli credential create --credential_type  "Machine" --name ${ORG%-org}-endpoint --organization "${ORG}" \
                            --inputs '{"username": "epuser", "ssh_key_data": "@~/.ssh/'${ORG%-org}'-ssh-keypair"}'
~/awx-cli user create --username ${ORG%-org}-jobcreator --email jobcreator@${ORG}.example.com --password password
~/awx-cli user create --username ${ORG%-org}-operator   --email operator@${ORG}.example.com  --password password
~/awx-cli user grant --organization ${ORG} --role member ${ORG%-org}-jobcreator
~/awx-cli user grant --organization ${ORG} --role member ${ORG%-org}-operator

~/awx-cli team create --name ${ORG%-org}-jobcreators.grp --organization ${ORG}
~/awx-cli team create --name ${ORG%-org}-wfcreators.grp --organization ${ORG}
~/awx-cli team create --name ${ORG%-org}-operators.grp --organization ${ORG}

~/awx-cli teams grant ${ORG%-org}-jobcreators.grp --organization ${ORG} --role job_template_admin
~/awx-cli teams grant ${ORG%-org}-jobcreators.grp --project ${ORG%-org}-project --role use
~/awx-cli teams grant ${ORG%-org}-jobcreators.grp --inventory ${ORG%-org}-inventory --role use
~/awx-cli teams grant ${ORG%-org}-jobcreators.grp --credential ${ORG%-org}-endpoint --role use
~/awx-cli teams grant ${ORG%-org}-jobcreators.grp --credential ${ORG%-org}-githost --role use

~/awx-cli teams grant ${ORG%-org}-wfcreators.grp --organization ${ORG} --role workflow_admin
~/awx-cli teams grant ${ORG%-org}-wfcreators.grp --project ${ORG%-org}-project --role use
~/awx-cli teams grant ${ORG%-org}-wfcreators.grp --inventory ${ORG%-org}-inventory --role use
~/awx-cli teams grant ${ORG%-org}-wfcreators.grp --credential ${ORG%-org}-endpoint --role use

~/awx-cli users grant --team ${ORG%-org}-jobcreators.grp --role "member" ${ORG%-org}-jobcreator
~/awx-cli users grant --team ${ORG%-org}-wfcreators.grp --role "member" ${ORG%-org}-jobcreator
~/awx-cli users grant --team ${ORG%-org}-operators.grp --role "member" ${ORG%-org}-operator
~/awx-cli inventory_source update ${ORG%-org}-inventory-source
fi

if [ -r ~/.ssh/jumphost_key ];then
  ~/awx-cli credential create --credential_type  "ssh_jumphost_cred_type" --name ${ORG%-org}-jumphost --organization "${ORG}" \
                            --inputs '{"hostname": "'$(uname -n)'","username": "jhuser" , "ssh_key": "@~/.ssh/jumphost_key"}'
  ~/awx-cli teams grant ${ORG%-org}-jobcreator.grp --credential ${ORG%-org}-jumphost --role use
fi

echo "[created user list]"
~/awx-cli user list
\\
set +x

}

usage(){
# _   _
#| | | |___  __ _  __ _  ___
#| | | / __|/ _` |/ _` |/ _ \
#| |_| \__ \ (_| | (_| |  __/
# \___/|___/\__,_|\__, |\___|
#                 |___/

if [ $# -ge 1 ];then
printf "\033[1;31;40mError: $1\033[0m\n"
fi

cat << EOF
Usage ${0##*/}: <tasks>

 select following task or "all"
      01: install_package
      02: install_awx
      03: extract_assets
      04: build_endpoint
      05: setup_dockerhost
      06: setup_git_environment
      07: setup_awx_cli
      08: config: setup sample config after setup AWX environment.
      09: setup_jumphost

${0##*/}  01       ---> install prereq package only
${0##*/}  02       ---> install awx with pre-build images (version 21.3 only)
${0##*/}  all      ---> do all setup tasks (exclude config task)
                                   same as 01 02 03 04 05 06 07
${0##*/}  awx      ---> install only awx (no endpoints)
                                   same as 01 02 07
${0##*/}  ansbile  ---> install only ansible cli environment
                                   same as 01 03 04 05 06 07
${0##*/}  config   ---> install only ansible cli environment
                                   same as 08
${0##*/}  jumphost ---> install jumphost setting (create container)
                                   same as 09

you can set following environment for multi tenant environment.
\${AWXHOST:=localhost}
\${ORG:=my-org}
\${NODES:="node01 node02 node03"}

EOF
exit
}

##############
# main
##############

[ $# -eq 0 ] && usage

CMDLST=""

## argument validation
while [ $# -gt 0 ];
do
 case ${1:-XXX} in
   01|install_package)
      CMDLST="${CMDLST} installpackage"
      ;;
   02|install_awx)
      CMDLST="${CMDLST} installawx"
      ;;
   03|extract_assets)
      CMDLST="${CMDLST} extractassets"
      ;;
   04|build_endpoint)
      CMDLST="${CMDLST}
      buildendpoint
      connectawxnet"
      ;;
   connect_awxnet)
      CMDLST="${CMDLST} connectawxnet"
      ;;
   disconnect_awxnet)
      CMDLST="${CMDLST} disconnectawxnet"
      ;;
   05|setup_dockerhost)
      CMDLST="${CMDLST} setupdockerhost"
      ;;
   06|setup_git*)
      CMDLST="${CMDLST} setupgit"
      ;;
   07|setup_awx_cli)
      CMDLST="${CMDLST} setupawxcli"
      ;;
   08|config)
      CMDLST="${CMDLST} setupsampleconfig"
      ;;
   09|jumphost)
      CMDLST="${CMDLST} setupjumphost"
      ;;
   ansible)
      CMDLST="${CMDLST}
      installpackage
      extractassets
      buildendpoint
      setupdockerhost
      setupgit
      setupawxcli"
      ;;
   awx)
      CMDLST="${CMDLST}
      installpackage
      installawx
      setupawxcli"
      ;;
   all|ALL)
      CMDLST="${CMDLST}
      installpackage
      installawx
      extractassets
      buildendpoint
      connectawxnet
      setupdockerhost
      setupgit
      setupawxcli"
      ;;
   *)
     usage "Invalid argument: $1"
     ;;
 esac
 shift
done

set ${CMDLST}

BEGINEPOC=$(date +%s)

while [ $# -gt 0 ]
do
  perl -e 'print "BEGIN:>>> '${1:-XXX}': " . localtime(time) . "\n"'
  eval $1
  RC=$?
  set +x
  elapse=$(($(date +%s) - ${BEGINEPOC}))
  perl -e 'print "END:  >>> '${1:-XXX}': " . localtime(time) . " ('${elapse}'[sec])". "\n"'
  [ $RC -eq 0 ] || { set +x ; figlet -w 150 Someting Error Occurred. ; break ;}
  shift
done

figlet -w 150 Complete all tasks.
ENDEPOC=$(date +%s)
elapse=$((${ENDEPOC} - ${BEGINEPOC}))
printf "START: $(perl -e 'print localtime('$BEGINEPOC') ."\n"')\nEND:   $(perl -e 'print localtime('${ENDEPOC}') ."\n"')\nElapse: ${elapse} [sec]\n"
