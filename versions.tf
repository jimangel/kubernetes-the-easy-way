terraform {
  required_version = ">= 1.4.2"
  required_providers {
    digitalocean = { 
      source = "digitalocean/digitalocean"
      version = "~> 2.6.0" 
    }
    null = { version = "~> 3.1" }
    random = { version = "~> 3.1" }
  }
}
