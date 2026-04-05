## cd /Users/romaincomtet/Documents/vm/quickstart

`pulumi stack init dev` # or use your existing stack
`pulumi config set gcp:project silent-venture-492408-p9`

# optional overrides:

# pulumi config set zone europe-west1-b

# pulumi config set sshPublicKeyPath ~/.ssh/id_ed25519.pub

# set up compute api google cloud

gcloud services enable compute.googleapis.com --project=silent-venture-492408-p9

pulumi up
`pulumi config set desiredStatus TERMINATED && pulumi up` # stop
`pulumi config set desiredStatus RUNNING && pulumi up`

# start
