# sqlserver-pipeline-framework

This git repository acts as a template for new SQL Server projects.

## Usage

Clone this repository and run the "Create Git Repo from Template.ps1" file from a powershell terminal.

You will be prompted for a name of a new repository and it will copy itself over there and replace all template references to your new chosen name.

After that, inside your new repo, you need to run the "bootstrap.ps1" script to make sure you have the required powershell modules and other settings in your projects to be able to start.

Lastly, if you want to run SQL Server on docker, it would help your if you ran the "example - write settings file.ps1" script to write your dev environment file that will store the password for your sa account on your sql server environment on docker.

## Features

You will be given a boilerplate development environment for a SQL Server project.
You will also have an entire build pipeline on your local machine.

- SQL Server instance running on docker with docker-compose
- A SQL Server database project
- A tSQLt unit test project
- A C# project to produce a database upgrade program to enable continuous delivery of the database.
- An InvokeBuild script to orchestrate
  - dev environment configuration
  - build
  - unit tests
  - schema integrity checks
  - upgrade testing and dev environment deployment.


## Prerequisites

- Git
- Visual Studio (community is free)
- SQL Server Data Tools for Visual Studio.
- PowerShell
- Docker or SQL Server express or higher
- dotnet core 3.1 or higher

## Developing with the framework

### Changes

### Migration scripts

### About SQL modules

### Unit tests


# kvar att göra
generate documentation of procs
choose docker sql server och localdb
Write about how to use the framework