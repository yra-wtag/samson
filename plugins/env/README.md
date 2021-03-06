## Env Plugin
Plugin to manage ENV settings for projects and write .env files during deploy.

Includes `/projects/:permalink/environment?deploy_group=permalink` endpoint that returns the `.env` content
for a project and deploy_group.

## GitHub to manage environment variables
This plugin has an option to use a GitHub repository as source for environment variables. 
The DEPLOYMENT_ENV_REPO must be set in samson's start up. Each project must opt-in to it via project settings.

The expected structure of this repository is a directory named `generated` with a sub directory for each 
_project permalink_ samson deploys.  Within this directory for a project are the deploy group .env files using the name
of the _deploy group permalink_ with a `.env` extension.  For a project with the permalink `data_processor` and 
the deploy group permalinks `staging1`, `prod1` and `prod2` samson expects to see this directory tree:
```bash
.
├── deploy_groups.yml
├── generated
│   └── fake_project
│       ├── staging1.env
│       ├── prod1.env
│       └── prod2.env
├── projects
│   └── fake_project.env.erb
└── shared
    └── env_three.env.erb
```
The contents of the `.env` file is a sequence of environment variable key and value pairs.
```bash
# cat generated/fake_project/staging1.env
MAX_RETRY_ATTEMPTS=10
SECRETE_TOKEN=/secrets/SECRET_TOKEN
RAILS_THREAD_MIN=3
RAILS_THREAD_MAX=5 
```
###### Merging enviroment variables stored in the database with those in the repo 
The generated enviornment variables is the merger of deploy_group env variables, if the samson `deploy_group plugin` is 
activated, the `project` environment variables in the samson database and the environment variables in the github `repo`.
The order of precedence for variables with the same key name: `deploy_group` replaces `project` which replaces `repo` variables.
