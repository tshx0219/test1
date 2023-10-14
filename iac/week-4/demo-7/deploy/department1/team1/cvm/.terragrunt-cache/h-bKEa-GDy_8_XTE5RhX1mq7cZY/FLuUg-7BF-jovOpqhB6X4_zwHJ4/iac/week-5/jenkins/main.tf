module "vpc" {
  source     = "../../module/vpc"
  secret_id  = var.secret_id
  secret_key = var.secret_key
}

module "cvm" {
  source        = "../../module/cvm"
  secret_id     = var.secret_id
  secret_key    = var.secret_key
  password      = var.password
  memory        = 16
  vpc_id        = module.vpc.vpc_id
  subnet_id     = module.vpc.subnet_id
  instance_name = "jenkins"
}

module "cloudflare" {
  source = "../../module/cloudflare"
  domain = var.domain
  prefix = var.prefix
  ip     = module.cvm.public_ip
  values = ["jenkins", "sonar", "tekton", "argocd"]
}

resource "null_resource" "connect_ubuntu" {
  depends_on = [module.k3s]
  connection {
    host     = module.cvm.public_ip
    type     = "ssh"
    user     = "ubuntu"
    password = var.password
  }

  triggers = {
    script_hash = filemd5("${path.module}/init.sh.tpl")
  }

  provisioner "file" {
    destination = "/tmp/init.sh"
    content = templatefile(
      "${path.module}/init.sh.tpl",
      {
        "prefix" : "${var.prefix}"
        "domain" : "${var.domain}"
        "harbor_password" : "${var.harbor_password}"
      }
    )
  }

  provisioner "file" {
    destination = "/tmp/jenkins-service-account.yaml"
    source      = "${path.module}/yaml/jenkins-service-account.yaml"
  }

  provisioner "file" {
    destination = "/tmp/jenkins-values.yaml"
    content = templatefile(
      "${path.module}/yaml/values.yaml.tpl",
      {
        "prefix" : "${var.prefix}"
        "domain" : "${var.domain}"
      }
    )
  }

  provisioner "file" {
    destination = "/tmp/harbor-url-secret.yaml"
    content = templatefile(
      "${path.module}/yaml/harbor-url.yaml.tpl",
      {
        "prefix" : "${var.prefix}"
        "domain" : "${var.domain}"
      }
    )
  }

  provisioner "file" {
    destination = "/tmp/sonar-values.yaml"
    content = templatefile(
      "${path.module}/yaml/sonar-values.yaml.tpl",
      {
        "prefix" : "${var.prefix}"
        "domain" : "${var.domain}"
        "sonar_password" : "${var.password}"
      }
    )
  }

  provisioner "file" {
    destination = "/tmp/tekton-dashboard-ingress.yaml"
    content = templatefile(
      "${path.module}/yaml/tekton-dashboard-ingress.yaml.tpl",
      {
        "prefix" : "${var.prefix}"
        "domain" : "${var.domain}"
      }
    )
  }

  provisioner "file" {
    destination = "/tmp/tekton-listener-ingress.yaml"
    content = templatefile(
      "${path.module}/yaml/tekton-listener-ingress.yaml.tpl",
      {
        "prefix" : "${var.prefix}"
        "domain" : "${var.domain}"
      }
    )
  }

  provisioner "file" {
    destination = "/tmp/github-personal-token.yaml"
    content = templatefile(
      "${path.module}/yaml/github-personal-token.yaml.tpl",
      {
        "github_username" : "${var.github_username}"
        "github_personal_token" : "${var.github_personal_token}"
      }
    )
  }

  provisioner "file" {
    destination = "/tmp/tekton-git-repositry-secret.yaml"
    content = templatefile(
      "${path.module}/yaml/tekton-git-repositry-secret.yaml.tpl",
      {
        "github_username" : "${var.github_username}"
        "github_personal_token" : "${var.github_personal_token}"
      }
    )
  }

  provisioner "file" {
    destination = "/tmp/github-pat-secret-text.yaml"
    content = templatefile(
      "${path.module}/yaml/github-pat-secret-text.yaml.tpl",
      {
        "github_personal_token" : "${var.github_personal_token}"
      }
    )
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/init.sh",
      "sh /tmp/init.sh",
    ]
  }
}

module "k3s" {
  source      = "../../module/k3s"
  public_ip   = module.cvm.public_ip
  private_ip  = module.cvm.private_ip
  server_name = "k3s-hongkong-1"
}

resource "local_sensitive_file" "kubeconfig" {
  content  = module.k3s.kube_config
  filename = "${path.module}/config.yaml"
}

