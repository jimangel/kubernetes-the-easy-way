terraform {
  required_version = ">= 0.12"
  required_providers {
    digitalocean = {
      version = "~> 1.17"
    }
    null = {
      version = "~> 2.1"
    }
  }
}