# Oracle Cloud 백엔드 자동배포

## 목표

- `main` 브랜치에 push 하면 GitHub Actions가 백엔드 jar를 빌드함.
- 빌드한 jar를 Oracle Cloud VM으로 복사함.
- VM에서 `systemd` 서비스를 재시작함.

## 레포에 추가된 파일

- `.github/workflows/deploy-backend.yml`
- `deploy/oracle/deploy-backend.sh`
- `deploy/oracle/pero-backend.service.template`
- `deploy/oracle/pero-backend.env.example`

## GitHub Secrets

- `OCI_HOST`: Oracle Cloud VM 공인 IP
- `OCI_USER`: 보통 `opc`
- `OCI_SSH_KEY`: VM 접속용 private key 전체 내용

## 서버 1회 설정

### 1. Java 21 설치

```bash
sudo dnf install -y jdk-21-headless
java -version
```

### 2. 배포 디렉토리 준비

```bash
sudo mkdir -p /opt/pero/backend
sudo mkdir -p /etc/pero
sudo chown -R opc:opc /opt/pero/backend
```

### 3. env 파일 준비

```bash
sudo cp deploy/oracle/pero-backend.env.example /etc/pero/pero-backend.env
sudo chown root:root /etc/pero/pero-backend.env
sudo chmod 640 /etc/pero/pero-backend.env
```

- 처음에는 비워 둬도 됨.
- 추가 설정이 생기면 `/etc/pero/pero-backend.env`에 넣으면 됨.

## 네트워크 권장

- `22/tcp`: 본인 IP만 허용
- `80/tcp`, `443/tcp`: 외부 공개 시 허용
- `8080/tcp`: 테스트용으로만 열고, 운영 시에는 Nginx 뒤에 두는 편이 안전함

## 동작 방식

1. `main`에 push 함
2. GitHub Actions가 `backend`에서 `./gradlew test bootJar` 실행함
3. jar와 배포 스크립트를 VM의 `/tmp`로 복사함
4. 원격에서 `deploy/oracle/deploy-backend.sh`를 실행함
5. `/opt/pero/backend/app.jar` 교체 후 `pero-backend.service` 재시작함
6. `http://127.0.0.1:8080/api/health`로 헬스체크함

## 주의

- 현재 워크플로는 Oracle Linux VM + `opc` 사용자를 기본으로 둠.
- 다른 사용자 계정을 쓰면 `OCI_USER`만 바꾸면 됨.
- 서비스 외부 노출까지 하려면 나중에 Nginx reverse proxy를 붙이는 게 좋음.
- 현재 자동배포 대상은 백엔드만임.
