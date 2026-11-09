// Runs once at Jenkins start-up (init.groovy.d): URL, admin user, the registry credential from the
// environment, and the menu-board pipeline job. Nothing here prints the secret.
import jenkins.model.*
import hudson.security.*
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.*
import com.cloudbees.plugins.credentials.impl.*
import com.cloudbees.plugins.credentials.common.*
def j = Jenkins.get()
def loc = JenkinsLocationConfiguration.get(); loc.setUrl("http://localhost:8080/"); loc.save()
if (!(j.getSecurityRealm() instanceof HudsonPrivateSecurityRealm)) {
  def realm = new HudsonPrivateSecurityRealm(false); realm.createAccount("admin", "admin"); j.setSecurityRealm(realm)
  def strat = new FullControlOnceLoggedInAuthorizationStrategy(); strat.setAllowAnonymousRead(false); j.setAuthorizationStrategy(strat)
}
def user = System.getenv("REG_USER"); def pass = System.getenv("REG_PASS")
if (user && pass) {
  def store = j.getExtensionList("com.cloudbees.plugins.credentials.SystemCredentialsProvider")[0].getStore()
  def existing = CredentialsProvider.lookupCredentials(StandardUsernamePasswordCredentials, j, null, null).find { it.id == "dockerhub-credentials" }
  if (existing) store.removeCredentials(Domain.global(), existing)
  store.addCredentials(Domain.global(), new UsernamePasswordCredentialsImpl(CredentialsScope.GLOBAL, "dockerhub-credentials", "registry access", user, pass))
}
def repo = System.getenv("REPO_URL")
if (repo && j.getItem("menu-board") == null) {
  def xml = new File("/usr/share/jenkins/ref/menu-board-job.xml").text.replace("__REPO_URL__", repo)
  j.createProjectFromXML("menu-board", new ByteArrayInputStream(xml.getBytes("UTF-8")))
}
j.save()
