data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2404-lts"
}

resource "yandex_compute_instance" "monitoring" {
  name        = "momo-monitoring"
  platform_id = "standard-v2"
  zone        = "ru-central1-d"

  resources {
    core_fraction = 20
    cores         = 2
    memory        = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 10
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.momo_subnet.id
    nat       = true 
  }

  metadata = {
    ssh-keys = "ubuntu:${file("id_ed25519.pub")}"
  }
}
