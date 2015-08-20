# kb8or
Continuous Deployment Tool for deploying with kubernetes

## Features
Will deploy kubernetes from files intelligently...

1. Will monitor for health of containers (not just fire and forget)
2. Supports private registry override (will support differing environments)
3. Container version manipulation (from version files - e.g. version artefacts files)
4. Environment specific variables (for deployments to dev, pre-prod, production)

## Pre-requisites
1. Requires a kubernetes cluster
2. Either:

  2. Localy
     
     2. Requires Ruby

     3. The "kubectl" client
     
     4. ssh client (For tunnel option)
  
  3. Docker

## Install

1. Can be simply run as a container (no install)
2. Or locally:
   
   Requires Ruby and the "kubectl" client
   `bundle install`
   
   
## Usage

### As a container:
`docker run -it --rm -v ${PWD}:/var/lib/deploy quay.io/ukhomeofficedigital/kb8or --help`
### Locally:
`./kb8or.rb --help`

### Deploy an 'environment':

Deploy to "default" environment (usually vagrant):
`./kb8or.rb mydeploy.yaml`

Deploy to specific environment:
`./kb8or.rb mydeploy.yaml --env pre-production`

A deployment will do the following:

1. Any defaults.yaml will be loaded (from the same directory)
2. Any environment file will then be parsed (based on EnvFileGlobPath set in defaults)
3. Each deploy will be loaded and setting will be updated
4. kubectl will be run to setup the Kb8Server settings (typically set per environment)
4. Any .yaml files in the path specfified will be parsed and environment settings replaced. 

### Requires a defaults.yaml file

Typically at least the DefaultEnvName and EnvFileGlobPath will be set. Any settings are supported e.g.:

```yaml
---
DefaultEnvName: vagrant
EnvFileGlobPath: ../environments/config/*/kb8or.yaml
ContainerVersionGlobPath: ../artefacts/*_container_version
PrivateRegistry: 10.100.1.71:30000
```

### Sample deployment file

```yaml
---

ContainerVersionGlobPath: ../artefacts/*_container_version
PrivateRegistry: 10.250.1.203:5000
UsePrivateRegistry: false
NoAutomaticUpgrade: true

Deploys:
  - path: ../containers/cimgt/docker_registry/kb8
    NoAutomaticUpgrade: true
  - path: ../containers/cimgt/jenkins/kb8
    NoAutomaticUpgrade: true
  - path: ../containers/cimgt/cimgt_proxy/kb8
    UsePrivateRegistry: true
```
### Sample environment file

```yaml
---
Kb8Server: http://10.250.1.203:8080
PrivateRegistry: 10.250.1.203:30000

ceph_monitors:
  - 10.250.1.203:6789
  - 10.250.1.204:6789
  - 10.250.1.205:6789

jenkins_home_volume:
  name: jenkins-home
  hostPath:
    path: /var/lib/jenkins_home

jenkins_node_selector:
  id: "1"

```

### Sample replacement kubernetes yaml file

Here the following replacements will be made:

1. image name will be set to PrivateRegistry value (unless UsePrivateRegistry: false)
2. image version will be set to value in file: ../artefacts/jenkins_dind_container_version (see ContainerVersionGlobPath above)
3. The ${jenkins_home_volume} will be set to the compound value dependant on environment (e.g. use a ceph volume with the ceph_monitors set for ci_mgt not vagrant).

```yaml
---
apiVersion: v1
kind: ReplicationController
metadata:
  name: jenkins
  labels:
    name: jenkins
spec:
  replicas: 1
  selector:
    name: jenkins
  template:
    metadata:
      labels:
        name: jenkins
    spec:
      containers:
      - name: jenkins
        image: set.by.kb8or/jenkins_dind:v3
        args:
          - /usr/share/jenkins/ref/bash_jenkins.sh
        volumeMounts:
          - name: jenkins-home
            mountPath: /var/jenkins_home
          - name: docker-socket
            mountPath: /var/run/docker.sock
        ports:
          - name: jenkins
            containerPort: 8080
      volumes:
        - name: docker-socket
          hostPath:
            path: /var/run/docker.sock
        - ${jenkins_home_volume}
      nodeSelector: ${ jenkins_node_selector }
```

## TODO
5. Update controller to allow for rolling updates.

   1. Find the controller (using it's name).
      Discover is it's running (from the pods).
      
   2. Find the selector
  
   3. Run kubectl get pods with selector
  
7. Tail container logs during deployments...