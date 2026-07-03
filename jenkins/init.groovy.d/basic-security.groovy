import jenkins.model.*
import hudson.security.*
import hudson.security.csrf.DefaultCrumbIssuer

def instance = Jenkins.getInstance()

// ---------------------------------------------------------------------------
// Read admin credentials from environment variables injected at container
// startup (e.g. via Docker secrets or Kubernetes secret env refs).
// NEVER hard-code credentials here.
//
// Required env vars:
//   JENKINS_ADMIN_USER     - e.g. "admin"
//   JENKINS_ADMIN_PASSWORD - strong random password, min 16 chars
//
// Set these in docker-compose or your orchestrator; never commit values.
// ---------------------------------------------------------------------------
def adminUser     = System.getenv("JENKINS_ADMIN_USER")     ?: "admin"
def adminPassword = System.getenv("JENKINS_ADMIN_PASSWORD")

if (!adminPassword) {
    throw new IllegalStateException(
        "[SECURITY] JENKINS_ADMIN_PASSWORD env var is not set. " +
        "Refusing to start Jenkins with no admin password. " +
        "Set JENKINS_ADMIN_PASSWORD in your container environment."
    )
}

if (adminPassword.length() < 16) {
    throw new IllegalStateException(
        "[SECURITY] JENKINS_ADMIN_PASSWORD is too short (minimum 16 characters). " +
        "Use a strong, randomly generated password."
    )
}

println "[Security] Creating admin account from environment variable (no password in source)"
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount(adminUser, adminPassword)
instance.setSecurityRealm(hudsonRealm)

// Role-based access: only authenticated users have full control
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

// Enable CSRF protection
instance.setCrumbIssuer(new DefaultCrumbIssuer(true))

// Disable CLI over remoting (reduces attack surface)
instance.getDescriptor("jenkins.CLI").get().setEnabled(false)

instance.save()
println "[Security] Jenkins security realm configured successfully"