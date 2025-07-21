output "droplet_ip" {
  description = "Public IPv4 of the trading bot droplet"
  value       = digitalocean_droplet.trading_bot.ipv4_address
}
