# ==============================================================
# Jerney - Google Certificate Manager
#
# Provisions Google-managed SSL certificates for all four domains.
# No cert-manager needed — Google handles provisioning and renewal.
#
# Flow:
#   1. DNS Authorization per domain → Terraform outputs a CNAME record
#   2. Add that CNAME to your DNS provider (one-time manual step)
#   3. Certificate Manager provisions + auto-renews the SSL cert
#   4. Cert Map wires all four certs to the single GKE Gateway LB
# ==============================================================

resource "google_project_service" "certificate_manager" {
  service            = "certificatemanager.googleapis.com"
  disable_on_destroy = false
}

locals {
  domains = {
    argocd  = "argocd.nilkanthprojects.site"
    grafana = "grafana.nilkanthprojects.site"
    signoz  = "signoz.nilkanthprojects.site"
    jerney  = "jerney.nilkanthprojects.site"
  }
}

# ---- DNS Authorizations ----
# Each authorization generates a CNAME record you must add to your DNS provider.
# Certificate Manager uses this CNAME to prove domain ownership without
# provisioning a temporary load balancer (unlike ACME HTTP-01).
resource "google_certificate_manager_dns_authorization" "domains" {
  for_each = local.domains

  name   = "jerney-${each.key}-dns-auth"
  domain = each.value

  depends_on = [google_project_service.certificate_manager]
}

# ---- Google-managed SSL Certificates ----
resource "google_certificate_manager_certificate" "domains" {
  for_each = local.domains

  name = "jerney-${each.key}-cert"

  managed {
    domains            = [each.value]
    dns_authorizations = [google_certificate_manager_dns_authorization.domains[each.key].id]
  }

  depends_on = [google_certificate_manager_dns_authorization.domains]
}

# ---- Certificate Map ----
# The Gateway references this map by name via annotation.
# One map covers all four certs — GKE picks the right cert per SNI hostname.
resource "google_certificate_manager_certificate_map" "jerney" {
  name       = "jerney-cert-map"
  depends_on = [google_project_service.certificate_manager]
}

resource "google_certificate_manager_certificate_map_entry" "domains" {
  for_each = local.domains

  name         = "jerney-${each.key}-entry"
  map          = google_certificate_manager_certificate_map.jerney.name
  certificates = [google_certificate_manager_certificate.domains[each.key].id]
  hostname     = each.value

  depends_on = [google_certificate_manager_certificate_map.jerney]
}
