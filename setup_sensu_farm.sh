#!/bin/bash

export config=~/.scalr/default.yaml
export AWS_AMIBASE="ami-8d948ced"
export AWS_AMI_user="ubuntu"
export OSID=ubuntu-16-04
export AMINAME=Scalr-Chef-$OSID-60418
export AWS_DEFAULT_REGION="us-west-1"
export farm_tmp=sensu-farm.json
export FName=Sensu-Monitoring
export farm_template=$FName.json

# build the image
cd image
./packer build ubuntu_scalr.json 2>&1 | tee output.txt
export amiid=$(tail -2 output.txt | head -2 | awk 'match($0, /ami-.*/) { print substr($0, RSTART, RLENGTH) }')

# get the AWS AMI ID from the packer output
cat new-image.json | jq ".cloudImageId=\"$amiid\""| jq ".os.id=\"$OSID\""| jq ".cloudLocation=\"$AWS_DEFAULT_REGION\"" | jq ".name=\"$AMINAME\"" > $AMINAME.json

# import the AWS image into Scalr as Image
export imageid=$(scalr-ctl images register --stdin < $AMINAME.json | jq '.data.id' | tr -d '"')

# clean up
rm output.txt
rm $AMINAME.json
cd ..

# create Scalr Role
export scalr_role=$(scalr-ctl roles create --stdin < sensu_role.json | jq '.data.id')
echo $scalr_role
echo $imageid

# add image to Role
echo "scalr-ctl role-images create --imageId $imageid --roleId $scalr_role --debug"
scalr-ctl role-images create --imageId $imageid --roleId $scalr_role --debug

# add in scripts
cd scripts
for x in $(ls -b )
do
export SCRIPT_NAME=$x

# clean up first
echo "Cleaning up base.json file"
rm base.json

# create base script file
cat <<EOF >> base.json
{
   "timeoutDefault": 1,
   "description": "",
   "tags": [],
   "deprecated": false,
   "blockingDefault": true,
   "osType": "linux",
   "name": "$SCRIPT_NAME"
 }
EOF

scriptid=$(scalr-ctl --config $config scripts list | jq ".data[] | select(.name==\"$SCRIPT_NAME\").id")

if [ -z "$scriptid" ]
then
  echo "create base script"
  scriptid=$(scalr-ctl --config $config scripts create --stdin < base.json | jq .data.id)
fi

# get id
echo $scriptid

# convert script to json
export body=$(python -c 'import os, sys, json; y=open(os.environ["SCRIPT_NAME"], "r").read(); print(json.dumps(y))')

# clean up files
echo "Cleaning up json files"
rm $SCRIPT_NAME.json

# create import file
cat <<EOF >> $SCRIPT_NAME.json
{
  "body": $body
}
EOF

# create script version
scalr-ctl --config $config script-versions create --scriptId $scriptid --stdin < $SCRIPT_NAME.json
done
cd ..

# create custom events used
scalr-ctl --config $config events create --stdin < events/UchiwaRestart

# build farm

# Create farm and get ID
cat $farm_tmp | jq '.farm.name=env.FName' > $farm_template
export farmid=$(scalr-ctl --config $config farms create-from-template --stdin < $farm_template | jq '.data.id')
echo $farmid

# # launch farm
# scalr-ctl --config $config farms launch --farmId $farmid
# #give scalr time to kick off
# sleep 60
# # get server id
# scalr-ctl --config $config farms list-servers --farmId $farmid
# export serverid=`scalr-ctl --config $config farms list-servers --farmId $farmid | jq '.data[0].id'|tr -d '"'`
# export orchserverid='"'$serverid'"'
# echo $serverid
# echo $orchserverid
#  loop till the server is up and running
# while [ "$serverstatus" != "running" ]
#  do echo "Status: $serverstatus"
#  	sleep 5
# 	export serverstatus=`scalr-ctl --config $config servers get --serverId $serverid | jq '.data.status'| tr -d '"'`
# done
# # sleep 60 to give scalr time to run scripts
# sleep 60
#  get orchestration log id
# export orchlogid=`scalr-ctl --config $config scripts list-orchestration-logs | jq ".data[] | select(.server.id | contains($orchserverid)).id"| sed "s/\"//g"`
#  get orchestration logs
# scalr-ctl --config $config scripts get-orchestration-log --logEntryId $orchlogid | jq '.'
#  verify exit code
# if [ `scalr-ctl --config $config scripts get-orchestration-log --logEntryId $orchlogid | jq '.data.executionExitCode'` != 0 ]
#  then
#  exit 1
# fi
