# docker-syncthing
 Docker Swarm Syncthing with Cluster Manager

## Usage
Before deploying this stack to your swarm, you need to set Config values for User, Password, and API Key. The following commands will randomly generate appropriate values and create the Configs for your swarm:
```
openssl rand -base64 1024 | tr -d "/+" | head -c8 | docker config create syncthing_user -
openssl rand -base64 1024 | head -c16 | docker config create syncthing_password -
openssl rand -base64 1024 | tr -d "/+" | head -c32 | docker config create syncthing_apikey -
```
After the Config values have been created you can deploy the stack:
```
docker stack deploy -c syncthing.yml syncthing
```

## Manager Service
The Manager service will use Docker discovery services (i.e. DNS) to issue REST API calls via curl to each Syncthing service in the stack. During the initial start up of the stack, the Manager service will loop through it's configuration syncronization routine every 5 seconds until all nodes are properly syncronized. After that point it will atempt syncronization every 60 seconds for assurance.

## TODOs
 - Auto-config all folders, not just the default one.