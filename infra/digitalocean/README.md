# DigitalOcean Infrastructure

This directory contains infrastructure configuration for deploying the trading bot on DigitalOcean.

## Terraform

The Terraform configuration in `terraform/` provisions a single droplet. Copy `terraform.tfvars.example` to `terraform.tfvars` and set your DigitalOcean token before running:

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

## Ansible

The Ansible playbook in `ansible/` installs basic dependencies and clones the trading bot repository. Update `inventory.ini` with the droplet's IP address and run:

```bash
ansible-playbook -i inventory.ini setup_bot.yml
```

## Vagrant

A `Vagrantfile` is provided for running the bot locally in a
virtual machine. Start the VM from this directory and connect with:

```bash
vagrant up
vagrant ssh
```

Use this environment to experiment before deploying to DigitalOcean. Destroy the
VM with `vagrant destroy` when finished.

