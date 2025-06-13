# 👨🏼‍💻Deploying a 3 Tier AwsBlog Web Application on AWS👨🏼‍💻
<html>
  <body>
    <img src="awsBlog.drawio.png" alt="Description of image" >
    <p>  This project implements a high-availability WordPress deployment using a 3-tier architecture on AWS. It leverages Amazon EC2 instances for the Web and App tiers, and Amazon RDS for the MySQL database layer. The deployment follows best practices for scalability, separation of concerns, and fault tolerance.</p>
  </body>
</html>

# 1️⃣ Step 1: Domain & Certificate Setup  

## 🌐 A) Register or Use an Existing Domain  

### ➤ If You Already Own a Domain (e.g., from GoDaddy):  
- Login to your GoDaddy account  
- Go to **My Products** > Choose your domain (e.g., `awsBlog.com`)  
- Under **DNS Management**:  
  - Locate the **Nameservers** section  
  - Click **Change**  
  - Choose **Custom** > Add the 4 nameservers provided by AWS Route 53 (covered in the next step)  
  - Click **Save**  
---

## 🧭 B) Create a Hosted Zone in Route 53  

🔧 A hosted zone allows DNS record management for your domain.  

- Go to **AWS Console → Route 53 → Hosted Zones**  
- Click **Create hosted zone**  
  - **Domain name:** `awsBlog.com`  
  - **Type:** Public hosted zone  
  - **Comment:** (leave empty)  
- Click **Create hosted zone**  
- Route 53 will generate 4 NS (Name Server) records automatically  

💡 **Important:**  
- If you bought the domain on GoDaddy, update these nameservers in GoDaddy's DNS.  
- If bought via Route 53, this is auto-managed.  

---

## 🔐 C) Request SSL/TLS Certificate from ACM (AWS Certificate Manager)  

This enables HTTPS/SSL for your domain & subdomains.  

- Navigate to **ACM** in Tokyo Region (`ap-northeast-1`)  
- Click **Request a certificate**  
- Choose **Request a public certificate**  
- Click **Next**  
- Add domain names:  
  - `awsBlog.com`  
  - `www.awsBlog.com`  
  - `prod.awsBlog.com`  
  - `dr.awsBlog.com`  
- Choose **DNS validation (easier than email)**  
- Click **Request**  

---

## 📌 D) Validate the Certificate via DNS (from ACM to Route 53)  

Once requested, ACM will show DNS validation records:  

- These are **CNAME** records with random values  
- Go to **Route 53 → Your Hosted Zone for `awsBlog.com`**  
- For each domain/subdomain:  
  - Click **Create Record**  
  - **Type:** CNAME  
  - **Name:** (from ACM)  
  - **Value:** (from ACM)  
  - Click **Create record**  

⏳ **Wait for ACM to update status from Pending validation → Issued**  
✅ This can take **5–10 minutes**
 

# 2️⃣ Step 2: VPC and Subnet Setup  

## 🛡️ A) Create a Custom VPC (Virtual Private Cloud)  
A VPC is your isolated private network in AWS. You’ll divide it into subnets for routing traffic logically across Availability Zones.  

- Go to **AWS Console → VPC**  
- Click **Create VPC**  
- Choose **VPC only** (or **VPC with subnets** if you prefer a wizard)  

**Configuration:**  
- **Name tag:** `Prod-VPC`  
- **IPv4 CIDR block:** `10.0.0.0/16` (gives 65,536 IPs)  
- **Tenancy:** Default (shared hardware)  
- Click **Create VPC**  

---

## 🧱 B) Create Subnets (Across 2 AZs for HA)  
You need 6 subnets in total:  
- 2 for **NAT/ALB**  
- 2 for **Webservers**  
- 2 for **App & DB servers**  

🗂 Make sure each subnet is in a different Availability Zone (AZ) for fault tolerance.  

### 📍 1) NAT/ELB Subnets (Public)  
These subnets will host Load Balancers and NAT gateways.  
- **Prod-NAT-CLB-Subnet-1**  
  - **CIDR:** `10.0.5.0/28`  
  - **AZ:** `ap-northeast-1a`  
- **Prod-NAT-CLB-Subnet-2**  
  - **CIDR:** `10.0.10.0/28`  
  - **AZ:** `ap-northeast-1b`  

✅ Associate these with the **public route table** and enable **auto-assign public IP**.  

### 🌐 2) Webserver Subnets (Private)  
For hosting EC2 instances that run your frontend.  
- **Prod-Webserver-Subnet-1**  
  - **CIDR:** `10.0.15.0/24`  
  - **AZ:** `ap-northeast-1a`  
- **Prod-Webserver-Subnet-2**  
  - **CIDR:** `10.0.20.0/24`  
  - **AZ:** `ap-northeast-1b`  

### 🖥️ 3) App & DB Subnets (Private)  
For backend application logic and database.  
- **Prod-Appserver-Subnet-1**  
  - **CIDR:** `10.0.25.0/24`  
  - **AZ:** `ap-northeast-1a`  
- **Dr-Appserver-Subnet-2**  
  - **CIDR:** `10.0.30.0/24`  
  - **AZ:** `ap-northeast-1b`  
- **Prod-db-Subnet-1**  
  - **CIDR:** `10.0.35.0/24`  
  - **AZ:** `ap-northeast-1a`  
- **Dr-db-Subnet-2**  
  - **CIDR:** `10.0.40.0/24`  
  - **AZ:** `ap-northeast-1b`  

---

## 🛣️ C) Create Route Tables  

You need at least 2 route tables:  

### 🔹 Public Route Table (for NAT/ALB)  
- **Name:** `Prod-Public-RT`  
- **Route:** `0.0.0.0/0 → Internet Gateway`  
- Associate with:  
  - `Prod-NAT-CLB-Subnet-1`  
  - `Prod-NAT-CLB-Subnet-2`  

### 🔸 Private Route Table (for app/web/db)  
- **Name:** `Prod-Private-RT`  
- **Route:** `0.0.0.0/0 → NAT Gateway` (you’ll create it in the next step)  
- Associate with:  
  - Web, App, and DB subnets  

---

## 🔌 D) Create & Attach Internet Gateway  

Allows traffic in/out for public subnets.  
- Go to **VPC → Internet Gateways**  
- Click **Create Internet Gateway**  
- **Name:** `Prod-IGW`  
- Click **Create**, then **Attach to VPC → Prod-VPC**

# 3️⃣ Step 3: Security Groups Configuration

Security Groups act as virtual firewalls to control inbound and outbound traffic to your AWS resources.

--

## 🔐 A) Create Security Group for Classic Load Balancer (CLB)

- **Name:** `CLB-SG`
- **Description:** Allow HTTP/HTTPS from anywhere
- **VPC:** `Prod-VPC`

**Inbound Rules:**
| Type  | Protocol | Port Range | Source    |
|--------|----------|------------|-----------|
| HTTP   | TCP      | 80         | 0.0.0.0/0 |
| HTTPS  | TCP      | 443        | 0.0.0.0/0 |

**Outbound Rules:**  
- Allow all traffic (default)

---

## 🧩 B) Create Security Group for Web Servers

- **Name:** `Webserver-SG`
- **Description:** Allow traffic from CLB
- **VPC:** `Prod-VPC`

**Inbound Rules:**
| Type  | Protocol | Port Range | Source   |
|--------|----------|------------|----------|
| HTTP   | TCP      | 80         | CLB-SG   |
| SSH    | TCP      | 22         | Your IP  |

**Outbound Rules:**  
- Allow all traffic (default)

---

## ⚙️ C) Create Security Group for App Servers

- **Name:** `Appserver-SG`
- **Description:** Allow traffic from Web Servers
- **VPC:** `Prod-VPC`

**Inbound Rules:**
| Type       | Protocol | Port Range | Source        |
|-------------|----------|------------|---------------|
| Custom TCP  | TCP      | 3000-4000  | Webserver-SG  |

**Outbound Rules:**  
- Allow all traffic (default)

---

## 🛡️ D) Create Security Group for Database (RDS)

- **Name:** `DB-SG`
- **Description:** Allow MySQL/Aurora access from App Servers
- **VPC:** `Prod-VPC`

**Inbound Rules:**
| Type          | Protocol | Port Range | Source       |
|---------------|----------|------------|--------------|
| MySQL/Aurora  | TCP      | 3306       | Appserver-SG |

**Outbound Rules:**  
- Allow all traffic (default)

---

# 4️⃣ Step 4: Internet Gateway & NAT Gateway Setup

This step ensures **public subnets** have internet access via the Internet Gateway and **private subnets** can access the internet via the NAT Gateway.

---

## 🌐 A) Internet Gateway — Already Created & Attached in Step 2  
- IGW Name: `Prod-IGW`
- Attached to VPC: `Prod-VPC`

✅ No action needed if already done.

---

## 🔁 B) Create NAT Gateway (in Public Subnet)

NAT Gateway allows outbound internet access for private subnets.

1. Go to **VPC Console → NAT Gateways**
2. Click **Create NAT Gateway**
   - **Name:** `Prod-NAT-GW`
   - **Subnet:** `Prod-NAT-CLB-Subnet-1` (public subnet)
   - **Elastic IP:** Allocate new Elastic IP or use existing
3. Click **Create NAT Gateway**

---

## 🔁 C) Update Private Route Table to Use NAT Gateway

1. Go to **VPC Console → Route Tables**
2. Select `Prod-Private-RT`
3. Click **Routes → Edit Routes**
   - Add:
     - **Destination:** `0.0.0.0/0`
     - **Target:** `Prod-NAT-GW`
4. Click **Save routes**

✅ This allows private subnets (web/app/db) to access the internet via the NAT Gateway.

---

# 5️⃣ Step 5: EC2 Instances Creation (Frontend, Backend, Proxy)

---

## 🚀 A) Frontend EC2 Instances (Web Tier)

1️⃣ Go to **EC2 → Instances → Launch Instance**  
2️⃣ **Name:** `Prod-Frontend-1`  
3️⃣ **AMI:** Amazon Linux 2022 (or preferred OS)  
4️⃣ **Instance Type:** `t2.micro` (Free Tier eligible)  
5️⃣ **Key Pair:** Select existing or create new  
6️⃣ **Network Settings:**  
- VPC: `Prod-VPC`  
- Subnet: `Prod-Webserver-Subnet-1`  
- Auto-assign Public IP: **Disable**  
- Security Group: `Prod-Frontend-SG`

7️⃣ Configure Storage → Default 8 GiB (or as needed)  
8️⃣ Click **Launch**

✅ Repeat for:
- `Prod-Frontend-2` in `Prod-Webserver-Subnet-2`

---

## 🚀 B) Backend EC2 Instances (App Tier)

1️⃣ Go to **EC2 → Instances → Launch Instance**  
2️⃣ **Name:** `Prod-Backend-1`  
3️⃣ **AMI:** Amazon Linux 2022   
4️⃣ **Instance Type:** `t2.micro`  
5️⃣ **Key Pair:** Same as frontend  
6️⃣ **Network Settings:**  
- VPC: `Prod-VPC`  
- Subnet: `Prod-Appserver-Subnet-1`  
- Auto-assign Public IP: **Disable**  
- Security Group: `Prod-Backend-SG`

7️⃣ Configure Storage → Default or adjust  
8️⃣ Click **Launch**

✅ Repeat for:
- `Prod-Backend-2` in `Dr-Appserver-Subnet-2`

---

## 🚀 C) Proxy EC2 Instance (NGINX Reverse Proxy)

1️⃣ Go to **EC2 → Instances → Launch Instance**  
2️⃣ **Name:** `Prod-Proxy`  
3️⃣ **AMI:** Amazon Linux 2022
4️⃣ **Instance Type:** `t2.micro`  
5️⃣ **Key Pair:** Same as above  
6️⃣ **Network Settings:**  
- VPC: `Prod-VPC`  
- Subnet: `Prod-NAT-CLB-Subnet-1`  
- Auto-assign Public IP: **Enable**
- Security Group: `Prod-Proxy-SG`

7️⃣ Configure Storage → Default or adjust  
8️⃣ Click **Launch**

---

# 6️⃣ Step 6: Create Frontend and Backend Load Balancers (Classic Load Balancer - CLB)

we’ll set up two **Classic Load Balancers (CLB)** — one for the frontend (public-facing) and one for the backend (internal traffic).

---

## 🌐 A) Create Frontend Classic Load Balancer (Public)

- Go to **EC2 → Load Balancers → Create Load Balancer**
- Choose **Classic Load Balancer**
- **Name:** `Prod-Frontend-CLB`
- **Scheme:** Internet-facing
- **Listeners:**  
  - HTTP: 80 (add HTTPS 443 if SSL configured in ACM)
- **Availability Zones:**  
  - VPC: `Prod-VPC`
  - Select subnets: `Prod-NAT-CLB-Subnet-1`, `Prod-NAT-CLB-Subnet-2`

- **Security Group:** Attach or create a security group that allows:
  - HTTP: 80 (from `0.0.0.0/0`)
  - HTTPS: 443 (if SSL enabled)

- **Health Check:**  
  - Protocol: HTTP
  - Ping Path: `/`
  - Port: 80

- **Add EC2 instances:**  
  - Nginx proxy or frontend instances (prod)

---

## 🔒 B) Create Backend Classic Load Balancer (Internal)

- Go to **EC2 → Load Balancers → Create Load Balancer**
- Choose **Classic Load Balancer**
- **Name:** `Prod-Backend-CLB`
- **Scheme:** Internal
- **Listeners:**  
  - HTTP: 80
- **Availability Zones:**  
  - VPC: `Prod-VPC`
  - Select subnets: `Prod-Webserver-Subnet-1`, `Prod-Webserver-Subnet-2`

- **Security Group:** Attach or create a security group that allows:
  - HTTP: 80 (from frontend CLB SG or VPC CIDR)

- **Health Check:**  
  - Protocol: HTTP
  - Ping Path: `/`
  - Port: 80

- **Add EC2 instances:**  
  - App server instances (prod)

---

## ⚠️ Notes

- **Frontend CLB** accepts external traffic and forwards to Nginx or similar.
- **Backend CLB** only accessible internally, between tiers.
- Make sure your SSL certificates (from ACM) are attached to the frontend CLB if enabling HTTPS.
- Adjust health check paths based on your application (e.g., `/healthcheck`).

---
# 7️⃣ Step 7: Create Database Subnet Group & RDS Instance

 we’ll set up the DB subnet group and the RDS database for production with DR readiness.

---

## 🗂 A) Create Database Subnet Group

A DB subnet group tells RDS where it can launch instances (across multiple AZs for high availability).

- Go to **RDS → Subnet Groups → Create DB Subnet Group**
- **Name:** `prod-db-subnet-group`
- **Description:** `Production DB subnet group`
- **VPC:** `Prod-VPC`
- **Subnets:**  
  - `Prod-db-Subnet-1 (ap-northeast-1a)`
  - `Dr-db-Subnet-2 (ap-northeast-1b)`
- Click **Create**

---

## 🛢️ B) Create RDS Instance

- Go to **RDS → Databases → Create Database**
- Choose **Standard Create**
- Engine: `MySQL` (or preferred engine)
- Version: `latest stable`
- Templates: `Production`
- **DB Instance Identifier:** `prod-db`
- **Master Username:** `admin`
- **Master Password:** `your-secure-password`
- **DB Instance Class:** `db.t3.micro` (or as per your size/Free Tier)
- **Multi-AZ Deployment:** ✅ Enabled (recommended for DR)
- **Storage Type:** `General Purpose (SSD)`  
- **Allocated Storage:** e.g. `20 GiB`  

### Connectivity
- **VPC:** `Prod-VPC`
- **Subnet group:** `prod-db-subnet-group`
- **Public access:** `No`
- **VPC security group:** select or create SG to allow DB access only from App servers
- **Availability zone:** (let AWS handle for Multi-AZ)

### Additional Config
- **Backup retention period:**  (or as needed)
- **Encryption:** Disabled (if needed)
- **Monitoring:** Disable Enhanced Monitoring (optional)

- Click **Create Database**

---

## ⚠️ Notes

- Ensure your app servers' security groups allow outbound to the DB security group (MySQL port 3306).
- RDS will automatically handle failover in case of AZ failure due to Multi-AZ setup.
- Regularly snapshot your DB or enable automated backups.

---
# 8️⃣ Step 8: S3 Bucket for Config Uploads

In this step, we will create an S3 bucket to store and manage configuration files, backups, or static assets.

---

## 🗂 A) Create S3 Bucket

- Go to **S3 → Create bucket**
- **Bucket name:** `prod-config-uploads-greenscloud`
- **Region:** `ap-northeast-1 (Tokyo)`

### Settings
- **Block all public access:** ✅ Enabled (default)
- **Versioning:** ✅ Enabled (recommended for config backups)
- **Encryption:** ✅ Enable SSE-S3 (or SSE-KMS if using KMS key)

Click **Create bucket**

---
# 9️⃣STEP 9: Configure Remote Access to Web, App, and DB Servers

## A) Launch EC2 Instances for SSH
- Navigate to **EC2 > Instances > Launch Instance**
- Configure the following:
  - **Name**: `Prod-Host` or `Dr-Host`
  - **AMI**: Amazon Linux 2022
  - **Instance Type**: `t2.micro`
  - **Key Pair**:
    - Use existing or create new key: `Prod-<REGION>-Key`
  - **Network**:
    - **VPC**: `Prod-VPC`
    - **Subnet**: `Prod-NAT-CLB-Subnet-1` or `Dr-NAT-CLB-Subnet-2`
    - **Auto-assign Public IP**: Enable
  - **Security Group**: `All-TCP-Security-Group`
- Click **Launch Instance**

## B) Create IAM Role with AmazonS3ReadOnlyAccess
- Navigate to **IAM > Roles**
- Click **Create Role**
  - **Trusted Entity**: EC2
  - **Permissions**: Attach `AmazonS3ReadOnlyAccess`
  - **Role Name**: `EC2-AmazonS3ReadOnlyAccess`
- Click **Create Role**

## C) SSH Access Using PuTTY (Windows)

### 1. Convert `.pem` to `.ppk` using PuTTYgen
- Open **PuTTYgen**
- Click **Load** and choose your `.pem` file
- Click **Save private key** → Save as `.ppk`

### 2. Connect Using PuTTY
- Open **PuTTY**
  - **Host Name**: `ec2-user@<your-ec2-public-ip>`
  - Go to: **Connection → SSH → Auth**
    - Browse and select your `.ppk` file
- Click **Open**

### 3. Login Details
- Default Username: `ec2-user`
- Repeat the same to SSH into `Dr-Host`

# 🔟 Step 10: Auto Scaling Groups for Web & App Servers  

---

## ⚙️ A) Create Launch Template  
- Go to **EC2 → Launch Templates → Create Launch Template**  
- **Name:** `web-launch-template` / `app-launch-template`  
- **AMI:** Amazon Linux 2  
- **Instance Type:** t2.micro  
- **Key Pair:** `prod-key-pair`  
- **Security Group:** Web or App SG  
- **IAM Role:** `Prod-EC2-Role`  
- **User Data (optional):** Add startup script  

---

## 📈 B) Create Auto Scaling Group  
- Go to **EC2 → Auto Scaling Groups → Create Auto Scaling Group**  
- **Name:** `web-asg` / `app-asg`  
- **Launch Template:** Select the one created above  
- **VPC:** `Prod-VPC`  
- **Subnets:** Select multiple availability zones  
- **Load Balancer:** Attach ALB (if configured)  

---

## 📊 C) Configure ASG Settings  
- **Desired Capacity:** 1  
- **Min Capacity:** 1  
- **Max Capacity:** 3  
- **Health Check Type:** EC2 or ELB  
- **Health Check Grace Period:** 300 seconds  

---

## 🔄 D) Add Scaling Policies  
- **Target Tracking Scaling Policy:**  
  - Metric Type: `Average CPU Utilization`  
  - Target Value: 50%  

---

✅ Now your Web and App EC2 instances will automatically scale based on load.

---

1️⃣1️⃣ Step 11: Route 53 DNS & Health Check Integration
1️⃣2️⃣ Step 12: SSL/TLS Certificate Integration (Optional)
✅ Final Step: Application Access & Health Check Confirmation

✅ **Final Step: Application Access Test**
- Open browser and access:
  - `http://prod.awsBlog.in` for the **frontend**
  - `http://dr.awsBlog.in` for **disaster recovery**
- Confirm health check response from `/health.html`

# CONGRATULATIONS!! CONGRATULATIONS!!
---




     
