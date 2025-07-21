provider "digitalocean" {
  token = var.do_token
}

resource "digitalocean_droplet" "trading_bot" {
  name   = "trading-bot"
  region = var.region
  size   = "s-1vcpu-1gb"
  image  = var.image

  tags = ["trader"]
}
