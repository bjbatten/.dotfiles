backupPostgres(){
  DATE=`date +%Y-%m-%d:%H:%M:%S`
  echo "Backing up Postgres $DATE"
  pg_dumpall -U izeadev -h 127.0.0.1 | gzip > dbdump-$DATE.gz
  echo "Done"
}
switchtoPostgresDb(){
  if [ $# -eq 0 ]; then
    echo "Please provide container name"
  else
    CNAME="pg-$1"
    containerExists=$(docker ps -q -a -f name=$CNAME )
    if [[ -n "$containerExists" ]]; then
      stopallPostgres
      echo "Switching to [$CNAME]..."
      docker start $CNAME
      echo
      docker ps
    else
      echo
      docker ps
      echo
      echo "No such container [$CNAME]. Press Enter to create clone of current running db..."
      read -rs
      echo
      dockerizePostgresDb $1
    fi
  fi
}
stopallPostgres(){
  echo "Stopping all running Postgres 9.5 containers..."
  docker stop $(docker ps -q -f ancestor=postgres:9.5)
  echo
}
dockerizePostgresDb(){
  if [ $# -eq 0 ]; then
    echo "Please provide container name"
  else
    DATE=`date +%Y-%m-%d:%H:%M:%S`
    FILENAME="dbdump-$DATE.gz"
    CNAME="pg-$1"
    ORIGINALFOLDER=`pwd`
    echo "Backing up Postgres for [$CNAME] @ $DATE"
    echo "Filename: $FILENAME"
    cd ~
    mkdir db_backups;cd db_backups
    mkdir $CNAME;cd $CNAME
    pg_dumpall -U izeadev -h 127.0.0.1 | gzip > $FILENAME
    echo
    stopallPostgres
    echo "Making new container $CNAME..."
    docker run -d --name $CNAME \
      -e POSTGRES_USER=izeadev \
      -e POSTGRES_DB=exchange_development \
      -p 5432:5432 \
      postgres:9.5
    echo "Waiting a bit for $CNAME to start..."
    sleep 5
    echo
    echo "Importing db into [$CNAME] from backup @ $DATE..."
    sleep 1
    gzcat $FILENAME | docker exec -i $CNAME psql postgres -U izeadev
    echo
    docker ps
    echo
    cd $ORIGINALFOLDER
    echo "Done"
  fi
}
dockerizeFromBackup(){
  CNAME="pg-$1"
  FILENAME="$2"
  echo "Making new container [$CNAME] to inject $FILENAME into..."
  stopallPostgres
  echo "Making new container [$CNAME] to inject $FILENAME into..."
  docker run -d --name $CNAME \
    -e POSTGRES_USER=izeadev \
    -e POSTGRES_DB=exchange_development \
    -p 5432:5432 \
    postgres:9.5
  echo "Waiting a bit for $CNAME to start..."
  sleep 5
  echo
  echo "Importing db into [$CNAME] from file $FILENAME ..."
  sleep 1
  gzcat $FILENAME | docker exec -i $CNAME psql postgres -U izeadev
  echo
  docker ps
  echo
  echo "Done"
}

ecscon() {
  if [ $1 = "qa" ]; then
    1="qa1"
  fi

  echo "looking for $2 $1 service"
  if [ $2 = "sapphire" ]; then
    SERVICE_NAME="izea-$1-$2-api"
  elif [ $2 = "obsidian" ] || [ $2 = "diamond" ]; then
    SERVICE_NAME="izea-$1-$2-api-ext"
  elif [ $2 = "emerald" ] || [ $2 = "amethyst" ]; then
    SERVICE_NAME="izea-$1-$2-web"
  fi
  echo "SERVICE_NAME: $SERVICE_NAME"
  CLUSTER_ID=$(aws ecs list-clusters --query "clusterArns[?contains(@,'izea-qa-services-ecs-Cluster')]" --output text)
  echo "CLUSTER_ID: $CLUSTER_ID"

  TASK_ID=$(aws ecs list-tasks --cluster $CLUSTER_ID --service-name $SERVICE_NAME --desired-status "RUNNING" --query "taskArns[0]" --output text)
  echo "TASK_ID: $TASK_ID"

  CONTAINER_INSTANCE_ID=$(aws ecs describe-tasks --cluster $CLUSTER_ID --tasks $TASK_ID --query "tasks[0].containerInstanceArn" --output text)
  echo "CONTAINER_INSTANCE_ID: $CONTAINER_INSTANCE_ID"

  EC2_INSTANCE_ID=$(aws ecs describe-container-instances --cluster $CLUSTER_ID --container-instances $CONTAINER_INSTANCE_ID --query "containerInstances[0].ec2InstanceId" --output text)
  echo "EC2_INSTANCE_ID: $EC2_INSTANCE_ID"

  EC2_IP=$(aws ec2 describe-instances --instance-ids $EC2_INSTANCE_ID --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
  echo "EC2_IP: $EC2_IP"

  COM="sudo docker exec -it \$(sudo docker ps -f name=$SERVICE_NAME -q) /bin/bash"
  ssh -t `whoami`@$EC2_IP $COM
  #ssh `whoami`@$EC2_IP
}

rcon() {
  if [ $1 = "qa" ]; then
    STACK_NAME="\`izea-qa1-exchange\`"
    echo "Looking in QA Stack"
  elif [ $1 = "qa2" ]; then
    STACK_NAME="\`izea-qa2-exchange\`"
    echo "Looking in QA2 Stack"
  elif [ $1 = "qa3" ]; then
    STACK_NAME="\`izea-qa3-exchange\`"
    echo "Looking in QA3 Stack"
  fi

  if [ $2 = "rails" ]; then
    LAYER_NAME="\`Rails App Server Live\`"
    echo "Looking in Rails layer"
  elif [ $2 = "sidekiq" ]; then
    LAYER_NAME="\`Sidekiq Live\`"
    echo "Looking in Sidekiq layer"
  elif [ $2 = "solr" ]; then
    LAYER_NAME="\`Solr\`"
    echo "Looking in Solr layer"
  fi

  STACK_ID=$(aws opsworks describe-stacks --query "Stacks[?Name==${STACK_NAME}].StackId" --output text)
  LAYER_ID=$(aws opsworks describe-layers --stack-id $STACK_ID --query "Layers[?Name==${LAYER_NAME}].LayerId" --output text)
  INSTANCE_IP=$(aws opsworks describe-instances --layer-id $LAYER_ID --query "Instances[?Status == 'online']|[0:1].[PublicIp]" --output text)
  ssh `whoami`@$INSTANCE_IP
}

alias dbbackup=backupPostgres
alias dbdockerize=dockerizePostgresDb
alias dfb=dockerizeFromBackup
alias dbswitchto=switchtoPostgresDb
alias dbs=dbswitchto
#Docker
alias d='docker'
alias dr='d run'
alias db='d build'
alias dp='d ps'
alias dpa='dp -a'
alias di='d images'
alias ddi='di --quiet --filter "dangling=true"'
alias dv='d version'
alias drm='d rm'
alias drmi='d rmi'
alias drmdi='drmi $(ddi)'
alias dh='d history'
#Docker Compose
alias dc='docker-compose'
alias dcu='dc up'
alias dcr='dc rm -f'

alias chr="open -a \"Google Chrome\""
alias jira="chr \"https://izeaeng.jira.com/projects/IZEAEX?selectedItem=com.atlassian.jira.jira-projects-plugin:release-page\""

alias b='bundle'
alias fs="foreman s web=0,worker=1,search=1,scheduler=1,lucre=1,faye=1,u-messaging=0"
alias f="foreman s web=1,lucre=1,search=1"
alias fw="foreman s web=1,lucre=1,search=1,worker=1"
alias fso='foreman start'

alias g='git'
alias ga='git add .'
alias gco='git checkout'
alias gcm='git commit -m'
alias gd='git diff --color | diff-so-fancy'
alias gs='git status'
alias gpl='git pull'
alias gph='git push'
alias gb='git branch'
alias gm='git merge'

alias gstart='git flow feature start'
alias gfin='git flow feature finish'

alias izea='cd ~/Projects/izea-exchange'

alias l="LSCOLORS=gxfxcxdxbxegedabagacad ls -lahGp"
alias r='rake'
alias rkm='rake db:migrate'
alias rt='rake test'
alias ru='rake test:units'
alias rf='rake test:functionals'
alias ri='rake test:integration'
alias spt='spring testunit'
alias ss='spring stop'
alias ff='FF=true'
alias al='cat ~/.dotfiles/zsh/aliases.zsh | grep alias | less'
alias home='cd ~'
alias clean='cd frontend && npm prune && npm install && bower prune && bower install && izea'
alias sshqa='ssh brianbatten@52.87.197.62'
alias docs='cd ~/Projects/api_docs'
alias iserv='bundle exec rails server -p 3000 -b 127.0.0.1'
alias mess='cd ~/Projects/u-messaging'
alias sdocs='./api_docs.js server izeax'
alias am='cd ~/Projects/amethyst-marketer-web'
alias em='cd ~/Projects/emerald-creator-web'
alias obs='cd ~/Projects/obsidian-api'
alias sap='cd ~/Projects/sapphire-workflow-service'
alias tz='cd ~/Projects/topaz-notification-service'
alias os='overmind s'
alias pry='overmind c web'
alias seed='gemstone bootstrap'
alias dia='cd ~/Projects/diamond-auth-service'
alias dsd='d start pg-develop'
alias dsr='d start pg-release'
alias dsm='d start pg-master'
alias dsi='d start pg-imagu'
alias dsa='d stop pg-develop && d stop pg-release && d stop pg-master && d stop pg-imagu'
alias emtd='atom /Users/brianbatten/Projects/emerald-creator-web && atom /Users/brianbatten/Projects/emeraldtodo.md'
