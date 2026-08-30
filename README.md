# docker-router

Docker router to run multiple project in containers

# Why
Sometimes you need to run multiple projects which are using similar ports. So you will get message like

`Cannot start Docker Compose application. Reason: compose [start] exit status 1. Container nginx-proxy Starting Error response from daemon: driver failed programming external connectivity on endpoint nginx-proxy ( *** ): Bind for 0.0.0.0:80 failed: port is already allocated`

This solution is based on: https://olex.biz/2019/09/hosting-with-docker-nginx-reverse-proxy-letsencrypt/

# Usage
clone repository

`git clone https://github.com/safronik/docker-router.git ./`

run docker composer form the repo directory

`docker composer up -d`

append the proxy network and environment var to you front app(ngixn for example) in docker-compose.yml
```
services:
	webserver:
	...
		environment:
		  - VIRTUAL_HOST=some.loc
		  - VIRTUAL_PORT=80
		  - LETSENCRYPT_HOST=some.loc
		  - LETSENCRYPT_EMAIL=email@somewhere.tld
		networks:
			- proxy
networks:
  proxy:
    external: true
	name: nginx-proxy
```
Here is live example of docker-compose.yml:
```
version: '3' 

# nginx
services:
	webserver:
		build:
			context: ./nginx
			dockerfile: Dockerfile
		image: some/nginx
		container_name: some-nginx
		environment:
		  - VIRTUAL_HOST=some.loc
		  - VIRTUAL_PORT=80
		  - LETSENCRYPT_HOST=some.loc
		  - LETSENCRYPT_EMAIL=email@somewhere.tld
		volumes:
			- ../code:/code
			# - ../../config/php:/etc/nginx/
		networks:
			- proxy
			- app-network

...
other services
...

networks:
  proxy:
    external: true
	name: nginx-proxy
  app-network:
	driver: bridge
```
make as many apps as you want but don't forget to modify your hosts file with the similar line

`127.0.0.1 some.loc`

# Enjoy
