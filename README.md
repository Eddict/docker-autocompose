# docker-compo-decompo
This fork focuses on the combined Docker image, which provides both autocompose (generate docker-compose YAML from containers) and decomposerize (compose docker run commands from compose files and write them to a shell script) functionality. Use the combined image for all-in-one container management and conversion tasks.

## Docker Usage
This fork is focused on using prebuilt Docker images for autocompose and decomposerize. You do not need to build from source; simply pull and use the images as described below. For the original upstream image, see [Red5d/docker-autocompose](https://github.com/Red5d/docker-autocompose).

### Combined Image
Pull the combined image from GitHub (supports both x86 and ARM):
``` bash
docker pull ghcr.io/eddict/docker-compo-decompo:latest
```
If you have cloned or forked this repo, replace 'eddict' with your own GitHub username or organization (repo owner):
``` bash
docker pull ghcr.io/<repo-owner>/docker-compo-decompo:latest
```
Use the combined image to generate a docker-compose file from a running container or a list of space-separated container names or ids:
``` bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock ghcr.io/eddict/docker-compo-decompo autocompose <container-name-or-id> <additional-names-or-ids>...
```
To print out all containers in a docker-compose format:
``` bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock ghcr.io/eddict/docker-compo-decompo autocompose $(docker ps -aq)
```

### Individual Images
You can also use the individual images for autocompose and decomposerize separately.

#### Autocompose Image
Pull the autocompose image:
``` bash
docker pull ghcr.io/eddict/docker-autocompose:latest
```
Generate a docker-compose file:
``` bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock ghcr.io/eddict/docker-autocompose <container-name-or-id> <additional-names-or-ids>...
```

#### Decomposerize Image
Pull the decomposerize image:
``` bash
docker pull ghcr.io/eddict/docker-decomposerize:latest
```
Convert a docker-compose file to a shell script:
``` bash
docker run --rm -i ghcr.io/eddict/docker-decomposerize < docker-compose.yaml > docker-run.sh
```

---
This project is based on the original [Red5d/docker-autocompose](https://github.com/Red5d/docker-autocompose) and may contain additional features or modifications.

---
The decomposerize CLI is originally developed and maintained at [github.com/Decomposerize/decomposerize](https://github.com/Decomposerize/decomposerize).

## Contributing
When making changes, please validate the output from the script by writing it to a file (docker-compose.yml or docker-compose.yaml) and running "docker compose config" in the same folder with it to ensure that the resulting compose file will be accepted by docker compose.
