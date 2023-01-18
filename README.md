# Eliona mock #

The Eliona mock is a simple mock for development and testing purposes. Is provides the API and a simplified database as backend. Both, the database and the API are needed to develop and run apps and other Eliona components outside an Eliona environment. 

## Installation ##

You need a database initialized with mock objects and an Eliona API server. The API server is available as a docker image in Docker Hub.

- [Eliona API v2 server](https://hub.docker.com/repository/docker/eliona/api-v2)

It is best to start these images with Docker compose. You can use this `docker-compose.yml` as template. 

## Usage ##

The mock can be used with the following settings if you run the mock on localhost:

- `CONNECTION_STRING` = `postgres://postgres:secret@localhost:5432`
- `API_ENDPOINT` = `http://localhost:3000/v2`
- `API_TOKEN` = `secret`

To authenticate on API either the API key or an JWT bearer token can be used. As a default JWT the following HTTP header can be used. 

```
Authorization: eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJleHAiOjE4NjA4ODMxNzIsInJvbGUiOiJhZG1pbiIsImN1c3RfaWQiOiIwIiwicHJval9pZCI6IjAiLCJ1c2VyX2lkIjoiMCJ9.dIW8xMpx58zVEnl-ck_YanqYyfAZ0q0YSkPV3r_TvmY
```

By default, an app named `example` is registered in the database. So you can use this app name to communicate with Eliona. For other app names please change or add the app into the table `eliona_app`.

- `APPNAME` = `example`
