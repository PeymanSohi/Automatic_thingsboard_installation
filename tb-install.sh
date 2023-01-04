#!/bin/bash
echo
echo "checking network connectivity"
echo  
while true
do
    if ping -c 1 -W 5 1.1.1.1 1>/dev/null 2>&1 
    then
        echo "Connected!"
        sudo apt install cowsay -y > /dev/null 2>&1
        break
    else
        echo "Not Connected!"
        sleep 1
        break
    fi
done

echo
echo "><><><><><><><><><><><><><><>"
echo  

read -p 'database node: ' database_node
read -p 'thirdparty node: ' thirdparty_node
read -p 'resources node: ' resources_node
read -p 'local IP address (kafka): ' IP
read -p 'thingsboard web port: ' PORT

echo database node is $database_node
echo thirdparty node is $thirdparty
echo resources node is $resources_node
echo IP address is $IP
echo thingsboard port is $PORT

echo

echo "Run the following commands on your node(s)"
echo
echo on $database_node
echo
echo "      sudo mkdir /mnt/postgres-data"
echo "      sudo mkdir /mnt/cassandra-data"
echo
echo on $thirdparty_node
echo
echo "      sudo mkdir /mnt/zookeeper-data"
echo "      sudo mkdir /mnt/zookeeper-datalog"
echo "      sudo mkdir /mnt/kafka-logs"
echo "      sudo mkdir /mnt/kafka-app-logs"
echo "      sudo mkdir /mnt/kafka-config"
echo
echo on $resources_node
echo
echo "      sudo mkdir /mnt/tb-mqtt-transport-logs-0"
echo "      sudo mkdir /mnt/tb-mqtt-transport-logs-1"
echo "      sudo mkdir /mnt/tb-http-transport-logs-0"
echo "      sudo mkdir /mnt/tb-http-transport-logs-1"
echo "      sudo mkdir /mnt/tb-coap-transport-logs-0"
echo "      sudo mkdir /mnt/tb-coap-transport-logs-1"
echo

while true; do
    read -p "Are you sure to continue? (y,n) " yn
    case $yn in
        [Yy]* ) echo ; echo installing... ; break;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no.";;
    esac
done

cowsay "Loading..."
sleep 5
echo  

kubectl create ns thingsboard  
kubectl config set-context $(kubectl config current-context) --namespace=thingsboard
echo
echo "==============="
echo
echo "database installation"
echo
echo "==============="
echo
export selected_node=$database_node && envsubst < ./postgres/postgres-pv.yaml | kubectl apply -f -
kubectl apply -f ./postgres/postgres-pvc.yaml  
kubectl apply -f ./postgres/postgres-deployment.yaml  
kubectl apply -f ./postgres/postgres-service.yaml  
kubectl rollout status deployment/postgres

echo  
echo "CASSANDRA_REPLICATION_FACTOR should be greater or equal to 1.  CASSANDRA_REPLICATION_FACTOR --- OK"
kubectl apply -f ./cassandra/cassandra-configmap.yaml
export selected_node=$database_node && envsubst < ./cassandra/cassandra-pv.yaml | kubectl apply -f -  
kubectl apply -f ./cassandra/cassandra-pvc.yaml  
kubectl apply -f ./cassandra/cassandra-statefulset.yaml  
kubectl apply -f ./cassandra/cassandra-service.yaml  
kubectl rollout status statefulset/cassandra  
echo "execute query"
kubectl exec cassandra-0 -- bash -c "cqlsh -u cassandra -p cassandra -e \
                    \"CREATE KEYSPACE IF NOT EXISTS thingsboard \
                    WITH replication = { \
                        'class' : 'SimpleStrategy', \
                        'replication_factor' : 1 \
                    };\""
echo "OK"
echo
echo "==============="
echo
echo "database installation done"
echo
echo "==============="
echo  
echo "tb-node installation"
echo
echo "==============="
echo
kubectl apply -f ./tb-node/tb-node-db-configmap.yaml
kubectl apply -f ./tb-node/tb-node-configmap.yaml
export selected_node=$database_node && envsubst < ./tb-node/database-setup.yaml | kubectl apply -f - 
kubectl wait --for=condition=Ready pod/tb-db-setup --timeout=120s
kubectl exec tb-db-setup -- sh -c 'export INSTALL_TB=true; export LOAD_DEMO='true'; start-tb-node.sh; touch /tmp/install-finished;'
kubectl delete pod tb-db-setup
echo
echo "==============="
echo
echo "tb-node installation done"
echo
echo "==============="
echo  
echo "thirdparty installation"
echo
echo "==============="
echo
export selected_node_thirdparty=$thirdparty_node && envsubst < ./zookeeper/zookeeper-data-pv.yaml | kubectl apply -f -
export selected_node_thirdparty=$thirdparty_node && envsubst < ./zookeeper/zookeeper-datalog-pv.yaml | kubectl apply -f -
kubectl apply -f ./zookeeper/zookeeper-data-pvc.yaml
kubectl apply -f ./zookeeper/zookeeper-datalog-pvc.yaml
kubectl apply -f ./zookeeper/zookeeper-configmap.yaml
kubectl apply -f ./zookeeper/zookeeper-statefulset.yaml
kubectl apply -f ./zookeeper/zookeeper-service.yaml
echo
export selected_node_thirdparty=$thirdparty_node && envsubst < ./kafka/kafka-pv.yaml | kubectl apply -f -
kubectl apply -f ./kafka/kafka-pvc.yaml
kubectl apply -f ./kafka/kafka-configmap.yaml
export host=$IP && envsubst < ./kafka/kafka-statefulset.yaml | kubectl apply -f -
kubectl apply -f ./kafka/kafka-service.yaml
echo
export selected_node_thirdparty=$thirdparty_node && envsubst < ./redis/redis-deployment.yaml | kubectl apply -f -
kubectl apply -f ./redis/redis-service.yaml
echo
echo "==============="
echo
echo "thirdparty installation done"
echo
echo "==============="
echo
echo "resources installation"
echo
echo "==============="
echo
kubectl apply -f ./tb-node/tb-node-cache-configmap.yaml
echo
export selected_node_resources=$resources_node && envsubst < ./js-executor/tb-js-executor-deployment.yaml | kubectl apply -f -
echo
export selected_node_resources=$resources_node && envsubst < ./mqtt/tb-mqtt-transport-pv-1.yaml | kubectl apply -f -
export selected_node_resources=$resources_node && envsubst < ./mqtt/tb-mqtt-transport-pv-2.yaml | kubectl apply -f -
kubectl apply -f ./mqtt/tb-mqtt-transport-pvc-1.yaml
kubectl apply -f ./mqtt/tb-mqtt-transport-pvc-2.yaml
kubectl apply -f ./mqtt/tb-mqtt-transport-configmap.yaml
kubectl apply -f ./mqtt/tb-mqtt-transport-statefulset.yaml
kubectl apply -f ./mqtt/tb-mqtt-transport-service.yaml
echo
export selected_node_resources=$resources_node && envsubst < ./http/tb-http-transport-pv-0.yaml | kubectl apply -f -
export selected_node_resources=$resources_node && envsubst < ./http/tb-http-transport-pv-1.yaml | kubectl apply -f -
kubectl apply -f ./http/tb-http-transport-pvc-0.yaml
kubectl apply -f ./http/tb-http-transport-pvc-1.yaml
kubectl apply -f ./http/tb-http-transport-configmap.yaml
kubectl apply -f ./http/tb-http-transport-statefulset.yaml
kubectl apply -f ./http/tb-http-transport-service.yaml
echo
export selected_node_resources=$resources_node && envsubst < ./coap/tb-coap-transport-pv-0.yaml | kubectl apply -f -
export selected_node_resources=$resources_node && envsubst < ./coap/tb-coap-transport-pv-1.yaml | kubectl apply -f -
kubectl apply -f ./coap/tb-coap-transport-pvc-0.yaml
kubectl apply -f ./coap/tb-coap-transport-pvc-1.yaml
kubectl apply -f ./coap/tb-coap-transport-configmap.yaml
kubectl apply -f ./coap/tb-coap-transport-statefulset.yaml
kubectl apply -f ./coap/tb-coap-transport-service.yaml
echo
export selected_node_resources=$resources_node && envsubst < ./web-ui/tb-web-ui-deployment.yaml | kubectl apply -f -
kubectl apply -f ./web-ui/tb-web-ui-service.yaml
echo
export selected_node_resources=$resources_node && envsubst < ./tb-node/tb-node-statefulset.yaml | kubectl apply -f -
export selected_port=$PORT && envsubst < ./tb-node/tb-node-service.yaml | kubectl apply -f -
echo
echo "==============="
echo
echo "resources installation done"
echo
echo "==============="
echo
cowsay "installation compeleted successfuly"
echo
echo You can access thingsboard web on http://localhost:$PORT
echo