import * as fs from "fs";
import * as path from "path";
import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

const config = new pulumi.Config();
/** Billing / API project for the GCP provider (not inferred from gcloud or ADC). */
const project = new pulumi.Config("gcp").require("project");

const region = config.get("region") || "europe-west1";
const zone = config.get("zone") || "europe-west1-b";
const machineType = config.get("machineType") || "n2-standard-2";
const instanceName = config.get("instanceName") || "lab-kvm-1";
const sshUser = config.get("sshUser") || "romain";
const sshPublicKeyPath =
  config.get("sshPublicKeyPath") ||
  `${process.env.HOME ?? ""}/.ssh/id_ed25519.pub`;
const bootDiskSizeGb = config.getNumber("bootDiskSizeGb") ?? 50;
const bootImage =
  config.get("bootImage") || "ubuntu-os-cloud/ubuntu-2204-lts";
const desiredStatus = (config.get("desiredStatus") || "RUNNING").toUpperCase();
const enableNestedVirtualization =
  config.getBoolean("enableNestedVirtualization") ?? true;

function resolveSshPublicKeyPath(p: string): string {
  if (p.startsWith("~/")) {
    return path.join(process.env.HOME ?? "", p.slice(2));
  }
  return path.resolve(p);
}

const pubKeyResolved = resolveSshPublicKeyPath(sshPublicKeyPath);
if (!fs.existsSync(pubKeyResolved)) {
  throw new Error(
    `SSH public key file not found: ${pubKeyResolved} (set sshPublicKeyPath in Pulumi config)`
  );
}
const sshPublicKey = fs.readFileSync(pubKeyResolved, "utf8").trim();
const sshKeysMetadata = `${sshUser}:${sshPublicKey}`;

/** GCP Ubuntu images often give the metadata-created user sudo that asks for a password that was never set. */
if (!/^[a-z_][a-z0-9_-]{0,31}$/i.test(sshUser)) {
  throw new Error(
    "sshUser must be a simple POSIX username (no spaces or special characters)"
  );
}
const sudoersDropIn = "/etc/sudoers.d/90-pulumi-nopasswd";
const startupScript = `#!/bin/bash
set -euo pipefail
FILE=${sudoersDropIn}
LINE='${sshUser} ALL=(ALL) NOPASSWD:ALL'
if [[ ! -f "$FILE" ]] || ! grep -qF "NOPASSWD:ALL" "$FILE" || ! grep -qF "${sshUser}" "$FILE"; then
  echo "$LINE" > "$FILE"
  chmod 0440 "$FILE"
fi
`;

/** Ensures Compute Engine API is on (needs Service Usage API + IAM to enable services). */
const computeApi = new gcp.projects.Service("compute-api", {
  project,
  service: "compute.googleapis.com",
  disableOnDestroy: false,
});

const vm = new gcp.compute.Instance(
  "lab-vm",
  {
    project,
    name: instanceName,
    machineType,
    zone,
    allowStoppingForUpdate: true,
    desiredStatus:
      desiredStatus === "TERMINATED" ||
      desiredStatus === "RUNNING" ||
      desiredStatus === "SUSPENDED"
        ? desiredStatus
        : "RUNNING",
    bootDisk: {
      initializeParams: {
        image: bootImage,
        size: bootDiskSizeGb,
      },
    },
    networkInterfaces: [
      {
        network: "default",
        accessConfigs: [{}],
      },
    ],
    metadata: {
      "ssh-keys": sshKeysMetadata,
      "startup-script": startupScript,
    },
    tags: ["pulumi-lab-vm"],
    labels: {
      managed_by: "pulumi",
    },
    ...(enableNestedVirtualization
      ? {
          advancedMachineFeatures: {
            enableNestedVirtualization: true,
          },
        }
      : {}),
  },
  { dependsOn: [computeApi] }
);

const externalIp = vm.networkInterfaces.apply(
  (ifs) => ifs[0]?.accessConfigs?.[0]?.natIp ?? ""
);
const internalIp = vm.networkInterfaces.apply((ifs) => ifs[0]?.networkIp ?? "");

export const projectOutput = project;
export const regionOutput = region;
export const zoneOutput = zone;
export const instanceNameOutput = vm.name;
export const machineTypeOutput = machineType;
export const bootDiskSizeGbOutput = bootDiskSizeGb;
export const sshUserOutput = sshUser;
export const externalIpOutput = externalIp;
export const internalIpOutput = internalIp;
export const desiredStatusOutput = vm.desiredStatus;
export const sshCommand = pulumi.interpolate`ssh -o StrictHostKeyChecking=accept-new ${sshUser}@${externalIp}`;

/** Ephemeral public IPs can change after stop/start unless you attach a static address. */
export const stopViaPulumi =
  "pulumi config set desiredStatus TERMINATED && pulumi up";
export const startViaPulumi =
  "pulumi config set desiredStatus RUNNING && pulumi up";
export const gcloudStopCommand = `gcloud compute instances stop ${instanceName} --zone=${zone}`;
export const gcloudStartCommand = `gcloud compute instances start ${instanceName} --zone=${zone}`;
export const gcloudSshCommand = `gcloud compute ssh ${sshUser}@${instanceName} --zone=${zone}`;
