variable "do_token" {
  type        = string
  description = "DigitalOcean API token"
}

variable "region" {
  type        = string
  default     = "nyc3"
  description = "Region for the droplet"
}

variable "image" {
  type        = string
  default     = "ubuntu-22-04-x64"
  description = "Droplet image"
}
