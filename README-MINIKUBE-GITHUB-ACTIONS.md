# Local CI/CD to Minikube with GitHub Actions

This guide helps you deploy this project to your local Minikube cluster using GitHub Actions and a self-hosted runner.

## What this setup does

- Runs a workflow from GitHub Actions.
- Uses your own machine (self-hosted runner) to execute jobs.
- Builds backend and frontend images directly inside Minikube.
- Applies Kubernetes manifest from k8s/jerney-minikube.yaml.
- Updates deployment images to the commit tag.

## 1) Prerequisites on your local machine

Install and verify:

- Docker Desktop
- Minikube
- kubectl
- Git

Quick checks:

```powershell
docker version
minikube version
kubectl version --client
git --version
```

## 2) Start and verify Minikube

```powershell
minikube start --driver=docker
kubectl config use-context minikube
kubectl get nodes
kubectl get sc
```

Expected storage class for this project is hostpath.

## 3) Add a self-hosted runner to your repository

In your GitHub repository:

1. Open Settings.
2. Open Actions, then Runners.
3. Click New self-hosted runner.
4. Pick your OS (Windows) and architecture.
5. Copy the shown commands and run them in PowerShell on your machine.
6. Start the runner service.

When it is online, the workflow can run on your machine.

## 4) Workflow file used

The workflow is in:

- .github/workflows/github-actions.yml

It is triggered by:

- Manual run (workflow_dispatch)
- Push to main

## 5) Run the workflow

Option A: Manual run

1. Open GitHub Actions tab.
2. Select Local Minikube CI-CD.
3. Click Run workflow.

Option B: Push to main

```powershell
git add .
git commit -m "trigger local minikube workflow"
git push origin main
```

## 6) Verify deployment locally

After the workflow completes:

```powershell
kubectl get pods -n jerney
kubectl get svc -n jerney
minikube service jerney-frontend -n jerney --url
```

Open the URL returned by the last command.

## 7) Notes about local CD

- This works because the job runs on your machine, not on a GitHub-hosted runner.
- If runner is offline, deployment will not run.
- If you switch from docker-desktop context to minikube, keep context set to minikube.

## 8) Common troubleshooting

### Pods stuck in Pending for database

Cause:
- PVC was created with a different storageClass in a previous run.

Fix:
```powershell
kubectl -n jerney delete deployment jerney-db --ignore-not-found=true
kubectl -n jerney delete pvc jerney-db-pvc --ignore-not-found=true
kubectl apply -f k8s/jerney-minikube.yaml
```

### Backend stuck in Init:0/1

Cause:
- Database pod is not ready yet.

Fix:
```powershell
kubectl get pods -n jerney
kubectl logs -n jerney deploy/jerney-db
```

### Frontend or backend image mismatch

Fix:
```powershell
kubectl -n jerney get deploy -o wide
kubectl -n jerney rollout restart deployment/jerney-backend
kubectl -n jerney rollout restart deployment/jerney-frontend
```

## 9) Optional cleanup

```powershell
kubectl delete namespace jerney
minikube stop
```
