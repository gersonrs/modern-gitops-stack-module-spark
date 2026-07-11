resource "null_resource" "dependencies" {
  triggers = var.dependency_ids
}

resource "argocd_project" "this" {
  count = var.argocd_project == null ? 1 : 0

  metadata {
    name      = var.destination_cluster != "in-cluster" ? "spark-${var.destination_cluster}" : "spark"
    namespace = "argocd"
  }

  spec {
    description  = "SparkOperator application project for cluster ${var.destination_cluster}"
    source_repos = ["https://github.com/GersonRS/modern-gitops-stack-module-spark.git"]

    destination {
      name      = var.destination_cluster
      namespace = "processing"
    }

    orphaned_resources {
      warn = true
    }

    cluster_resource_whitelist {
      group = "*"
      kind  = "*"
    }
  }
}

data "utils_deep_merge_yaml" "values" {
  input = [for i in concat(local.helm_values, var.helm_values) : yamlencode(i)]
}

resource "argocd_application" "this" {
  metadata {
    name      = var.destination_cluster != "in-cluster" ? "spark-${var.destination_cluster}" : "spark"
    namespace = "argocd"
    labels = merge({
      "application" = "spark"
      "cluster"     = var.destination_cluster
    }, var.argocd_labels)
    annotations = {
      "argocd.argoproj.io/sync-wave" = "3"
    }
  }

  timeouts {
    create = "5m"
    delete = "5m"
  }

  wait = var.app_autosync == { "allow_empty" = tobool(null), "prune" = tobool(null), "self_heal" = tobool(null) } ? false : true

  spec {
    project = var.argocd_project == null ? argocd_project.this[0].metadata.0.name : var.argocd_project

    source {
      repo_url        = "https://github.com/GersonRS/modern-gitops-stack-module-spark.git"
      path            = "charts/spark-operator"
      target_revision = var.target_revision
      helm {
        release_name = "spark"
        values       = data.utils_deep_merge_yaml.values.output
      }
    }

    destination {
      name      = var.destination_cluster
      namespace = "processing"
    }

    sync_policy {
      dynamic "managed_namespace_metadata" {
        for_each = length(var.namespace_labels) > 0 ? [var.namespace_labels] : []
        content {
          labels = managed_namespace_metadata.value
        }
      }
      dynamic "automated" {
        for_each = toset(var.app_autosync == { "allow_empty" = tobool(null), "prune" = tobool(null), "self_heal" = tobool(null) } ? [] : [var.app_autosync])
        content {
          prune       = automated.value.prune
          self_heal   = automated.value.self_heal
          allow_empty = automated.value.allow_empty
        }
      }

      retry {
        backoff {
          duration     = "20s"
          max_duration = "2m"
          factor       = "2"
        }
        limit = "5"
      }

      sync_options = [
        "CreateNamespace=true",
        "Validate=true",
        "PrunePropagationPolicy=foreground",
        "PruneLast=true",
        "Replace=true",
        "ServerSideApply=true"
      ]
    }
  }

  depends_on = [
    resource.null_resource.dependencies,
  ]
}

resource "kubernetes_secret" "git_creds" {
  metadata {
    name      = "git-creds"
    namespace = "processing"
  }

  data = {
    known_hosts = file("${var.path_known_hosts}")
    ssh         = file("${var.path_ssh}")
  }

  depends_on = [
    resource.argocd_application.this
  ]
}

resource "kubernetes_secret" "minio_secret" {
  metadata {
    name      = "minio-secret"
    namespace = "processing"
  }

  data = {
    access-key        = "${var.storage.access_key}"
    secret-access-key = "${var.storage.secret_access_key}"
  }

  depends_on = [
    resource.argocd_application.this
  ]
}

resource "null_resource" "this" {
  depends_on = [
    resource.argocd_application.this,
  ]
}
