# .............................
# Enable Google services 
# .............................
resource "google_project_service" "gcp_services" {
  project = var.project_id
  for_each = toset([
    "compute.googleapis.com",
  ])
  service            = each.key
  disable_on_destroy = false
}

# .............................
#     (0) public IP & SSL certificate
# .............................

# public static IP address
resource "google_compute_global_address" "lb_demo" {
  name    = "xlb-gh-example-ip"
  project = local.project_id
}

# Take time!
# https://cloud.google.com/load-balancing/docs/ssl-certificates/troubleshooting
resource "google_compute_managed_ssl_certificate" "lb_demo" {
  name    = "lb-demo-ssl-cert"
  project = local.project_id

  managed {
    domains = ["demo.${var.domain}"]
  }
}



# .............................
# Backend 1: storage bucket 
# .............................

resource "google_storage_bucket" "storage_bucket" {
  name                        = "storage-bucket-demo-website"
  location                    = local.project_default_region
  storage_class               = "REGIONAL"
  force_destroy               = true
  uniform_bucket_level_access = true
  project                     = local.project_id
  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
}

resource "google_storage_bucket_object" "content_in_storage" {
  name       = "index.html"
  content    = "<html><body>hello world</body></html> "
  bucket     = google_storage_bucket.storage_bucket.name
  depends_on = [google_storage_bucket.storage_bucket]
}

resource "google_storage_bucket_object" "content_404" {
  name       = "404.html"
  content    = "<html><body>Not found- 404</body></html> "
  bucket     = google_storage_bucket.storage_bucket.name
  depends_on = [google_storage_bucket.storage_bucket]
}

# make bucket public  
# must relax policy constraints/iam.allowedPolicyMemberDomains if set to something  more strict than Google default
resource "google_project_organization_policy" "iam_allowedPolicyMemberDomains" {
  project    = local.project_id
  constraint = "iam.allowedPolicyMemberDomains"

  restore_policy {
    default = true
  }
}

resource "google_storage_bucket_iam_member" "iam_storage_bucket" {
  bucket = google_storage_bucket.storage_bucket.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
  depends_on = [
    google_storage_bucket.storage_bucket,
    google_project_organization_policy.iam_allowedPolicyMemberDomains
  ]
}

# .............................
# Backend 2: backend bucket 
# .............................

resource "google_compute_backend_bucket" "backend_bucket" {
  project     = var.project_id
  name        = "default-backend-bucket"
  description = "Backend for demo site"
  bucket_name = google_storage_bucket.storage_bucket.name
  enable_cdn  = true
  depends_on = [
    google_storage_bucket.storage_bucket,
    google_project_service.gcp_services["compute.googleapis.com"]
  ]
}

# .............................
#     (3)  URL Map = setup LB
# .............................

resource "google_compute_url_map" "lb_demo" {
  project     = local.project_id
  name        = "lb-demo-url-map"
  description = "map to backend bucket & a NEG for cloud run"

  default_service = google_compute_backend_bucket.backend_bucket.id

  host_rule {
    hosts        = ["*"]
    path_matcher = "default-matcher"
  }

  path_matcher {
    name            = "default-matcher"
    default_service = google_compute_backend_bucket.backend_bucket.id

    # path_rule {
    #   paths   = ["/api", "/api/*"]
    #   service = google_compute_backend_service.serverless.id
    # }
  }

  depends_on = [
    google_compute_backend_bucket.backend_bucket,
    # google_compute_backend_service.serverless
  ]
}


# .............................
#       (4)    setup frontend with target proxy
# .............................

resource "google_compute_target_https_proxy" "lb_demo" {
  project  = local.project_id
  provider = google-beta
  name     = "lb-demo-https-proxy"

  url_map = google_compute_url_map.lb_demo.id
  ssl_certificates = [
    google_compute_managed_ssl_certificate.lb_demo.id
  ]

  depends_on = [
    google_compute_managed_ssl_certificate.lb_demo,
    google_compute_url_map.lb_demo
  ]
}

# .............................
#       (5)  Forwarding rules
# .............................

resource "google_compute_global_forwarding_rule" "lb_demo" {
  project = local.project_id
  name    = "demo-rule"
  target  = google_compute_target_https_proxy.lb_demo.id
  # check the link for difference between type of load balancers  https://docs.cloud.google.com/load-balancing/docs/application-load-balancer
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = 443 # or other e.g. for ssl
  ip_address            = google_compute_global_address.lb_demo.address
  depends_on = [
    google_compute_target_https_proxy.lb_demo,
    google_compute_global_address.lb_demo
  ]
}



