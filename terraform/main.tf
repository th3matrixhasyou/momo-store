terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"

  backend "s3" {}
}

provider "yandex" {
  service_account_key_file = "key.json"
  folder_id                = "b1glil3pipvjpvk62mlq"
  zone                     = "ru-central1-d"
}

# --- 1. Сеть и подсеть ---
resource "yandex_vpc_network" "momo_net" {
  name = "momo-network"
}

resource "yandex_vpc_subnet" "momo_subnet" {
  name           = "momo-subnet-a"
  zone           = "ru-central1-d"
  network_id     = yandex_vpc_network.momo_net.id
  v4_cidr_blocks = ["10.5.0.0/24"]
}

# --- 2. Сервисный аккаунт для кластера K8s и бакета статики ---
resource "yandex_iam_service_account" "k8s_sa" {
  name        = "momo-k8s-sa"
  description = "Service account for Kubernetes and S3"
}

resource "yandex_resourcemanager_folder_iam_member" "editor" {
  folder_id = "b1glil3pipvjpvk62mlq"
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.k8s_sa.id}"
}

# --- 3. Кластер Managed Kubernetes ---
resource "yandex_kubernetes_cluster" "momo_cluster" {
  name       = "momo-cluster"
  network_id = yandex_vpc_network.momo_net.id

  master {
    version = "1.35"
    zonal {
      zone      = yandex_vpc_subnet.momo_subnet.zone
      subnet_id = yandex_vpc_subnet.momo_subnet.id
    }
    public_ip = true
  }

  service_account_id      = yandex_iam_service_account.k8s_sa.id
  node_service_account_id = yandex_iam_service_account.k8s_sa.id

  depends_on = [
    yandex_resourcemanager_folder_iam_member.editor,
    yandex_vpc_subnet.momo_subnet
  ]
}

# --- 4. Группа узлов (прерываемые ВМ для экономии) ---
resource "yandex_kubernetes_node_group" "momo_node_group" {
  cluster_id = yandex_kubernetes_cluster.momo_cluster.id
  name       = "momo-nodes"
  version    = "1.35"

  scale_policy {
    fixed_scale {
      size = 1
    }
  }

  allocation_policy {
    location {
      zone = "ru-central1-d"
      # Параметр subnet_id отсюда удален в соответствии с требованиями провайдера
    }
  }

  instance_template {
    platform_id = "standard-v2"

    resources {
      memory = 4
      cores  = 2
    }

    boot_disk {
      type = "network-hdd"
      size = 32 # Возвращаем 32 ГБ для прохождения валидации API K8s
    }

    network_interface {
      # Подсеть теперь указывается только здесь
      subnet_ids = [yandex_vpc_subnet.momo_subnet.id]
      nat        = true
    }

    scheduling_policy {
      preemptible = true
    }
  }
}

# --- 5. Container Registry для образов ---
resource "yandex_container_registry" "momo_registry" {
  name      = "momo-registry"
  folder_id = "b1glil3pipvjpvk62mlq"
}

# --- 6. S3 бакет для раздачи статики фронтенда ---
resource "yandex_iam_service_account_static_access_key" "sa_static_key" {
  service_account_id = yandex_iam_service_account.k8s_sa.id
}

resource "yandex_storage_bucket" "momo_statics" {
  access_key = yandex_iam_service_account_static_access_key.sa_static_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa_static_key.secret_key
  bucket     = "momo-store-statics-neo"
  max_size   = 1073741824 # 1 GB

  depends_on = [yandex_resourcemanager_folder_iam_member.editor]
}
