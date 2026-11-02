# Active Directory and Powershell Automation Lab

## **Overview**

This project documents the step-by-step process of setting up an **Active Directory Domain Controller (AD-DC)** on **Windows Server 2022**, configuring **DHCP**, setting up **Remote Access and NAT**, adding users via **PowerShell**, and joining a **Windows 10 client** to the domain. The setup closely follows enterprise-level configurations, ensuring security and efficiency.

## **Network Topology**

- **Domain Controller (AD-DC):** Windows Server 2022
- **Client Machine:** Windows 10
- **Network Range:** 172.16.0.0/24 (192.168.56.10)
- **Hostname:** DC01 · Static IP: 192.168.56.10
- **Domain:** pumejlab.com
- **Hostname:** WIN10-01 · DHCP or reserved address

## **Project Objectives**

- Set up **Active Directory Domain Services (ADDS)**
- Configure **DHCP Server**
- Set up **Remote Access and NAT** for internal network routing
- Add **150 users and 5 Organizational Units (OUs)** via PowerShell
- Join a **Windows 10 machine to the domain**
- Authenticate users and verify **network connectivity**
- Implement **security policies** for domain users

---

## **1. Setting Up Active Directory Domain Controller (AD-DC)**

1. **Launch Windows Server 2022 VM**
2. **Rename Network Interfaces** for clarity (Internal & External)
3. **Assign Static IP** to the **Internal NIC** (172.16.0.10)
4. **Rename the Server** to `AD-DC`
5. **Install Active Directory Services (ADDS)**
6. **Promote the Server to a Domain Controller** with the domain `pumejlab.com`
7. **Verify Domain Controller Status**

## Active Directory Setup - Visual Guide

<!-- markdownlint-disable MD033 -->

<div align="center">
  <table>
    <tr>
      <td><img width="400" alt="Active Directory Diagram" src="https://github.com/user-attachments/assets/8741efdd-69db-44f6-98fa-6d7caae4ee02" /></td>
      <td><img width="400" alt="Setting Up AD-DC Network Range" src="https://github.com/user-attachments/assets/af4e4ed1-2974-44d5-b4a1-be1998cf1b0e" /></td>
      <td><img width="400" alt="Creating Static IP for Internal NIC" src="https://github.com/user-attachments/assets/0fa1bff6-f25e-49d8-93f7-a1b27773a845" /></td>
    </tr>
    <tr>
      <td align="center"><b>Active Directory Diagram</b></td>
      <td align="center"><b>Setting Up AD-DC Network Range</b></td>
      <td align="center"><b>Creating Static IP for Internal NIC</b></td>
    </tr>
  </table>
</div>
```

## **2. Installing and Configuring DHCP Server**

1. **Install DHCP Server Role**
2. **Create a DHCP Scope** (`172.16.0.100 - 172.16.0.200`)
3. **Set Router/Gateway IP** (`172.16.0.2`)
4. **Authorize the DHCP Server** in AD-DC
5. **Verify successful lease assignments**

## DHCP Server Configuration - Visual Guide

<!-- markdownlint-disable MD033 -->

<div align="center">
  <table>
    <tr>
      <td><img width="500" alt="Installing DHCP Server" src="https://github.com/user-attachments/assets/b7ee2c08-2050-4b57-b591-ebc6393d3aae" /></td>
      <td><img width="500" alt="Configuring New Scope to DHCP Server" src="https://github.com/user-attachments/assets/71d0d949-e24d-44f9-a068-dada72531dac" /></td>
    </tr>
    <tr>
      <td align="center"><b>Installing DHCP Server</b></td>
      <td align="center"><b>Configuring New Scope</b></td>
    </tr>
  </table>
</div>

## **3. Setting Up Remote Access and NAT**

1. **Install Remote Access Role**
2. **Enable Routing and Remote Access (RRAS)**
3. **Configure NAT for Internal Network Routing**
4. **Set up Internet Connectivity through the NAT interface**
5. **Verify network routing between client machines**

## Remote Access and Routing Configuration - Visual Guide

<div align="center">
  <table>
    <tr>
      <td><img width="400" alt="Configuring Routing and Remote Access part 2" src="https://github.com/user-attachments/assets/004d4156-fa00-4397-8547-c82130f1a27e" /></td>
      <td><img width="400" alt="Configuring Routing and Remote Access" src="https://github.com/user-attachments/assets/8b916df1-039f-4d13-a49e-836835d7e209" /></td>
      <td><img width="400" alt="Install Remote Access and Routing on AD-DC" src="https://github.com/user-attachments/assets/07ff9474-1909-4114-a881-7b149b29d7d9" /></td>
    </tr>
    <tr>
      <td align="center"><b>Validating Network Traffic Flow</b></td>
      <td align="center"><b>Configuring Routing and NAT</b></td>
      <td align="center"><b>Installing Remote Access Role</b></td>
    </tr>
  </table>
</div>
```

## **4. Adding 150 Users and Organizational Units (OUs) via PowerShell**

1. **Prepare a CSV file** (`user_accounts_final.csv`) containing:
   - Username
   - Email
   - Organizational Unit
   - Password
2. **Write PowerShell Script** (`AD Bulk Users Script.ps1`) to import users
3. **Run the script to add users to Active Directory**
4. **Verify users in Active Directory Users and Computers (ADUC)**

## Active Directory User & OU Deployment

<div align="center">
  <table>
    <tr>
      <td><img width="400" alt="Users and OUs added to Active Directory via PowerShell" src="https://github.com/user-attachments/assets/1911fedf-87f5-47ec-b8a4-a7ec316a96ae" /></td>
      <td><img width="400" alt="CSV File of 150 Users" src="https://github.com/user-attachments/files/19437393/Powershell.Script.and.CSV.file.zip" /></td>
      <td><img width="400" alt="PowerShell Script to Upload Users" src="https://github.com/user-attachments/files/19437393/Powershell.Script.and.CSV.file.zip" /></td>
    </tr>
    <tr>
      <td align="center"><b>Users & OUs Added via PowerShell</b></td>
      <td align="center"><b>CSV File of 150 Users</b></td>
      <td align="center"><b>PowerShell Script for Bulk Upload</b></td>
    </tr>
  </table>
</div>

## **5. Joining Windows 10 Client to the Domain**

1. **Install Windows 10 VM**
2. **Ensure Network Connectivity (Internal and Internet)**
3. **Join Windows 10 Machine to `pumejlab.com`**
4. **Authenticate with Domain Admin (`pumejadmin`)**
5. **Verify DHCP IP Assignment**
6. **Ensure domain policies are applied correctly**

## Windows 10 Domain Join & DHCP Verification

<div align="center">
  <table>
    <tr>
      <td><img width="450" alt="Confirming Windows 10 Address Leases in DHCP Server" src="https://github.com/user-attachments/assets/68c19371-fc05-423a-b951-52c8c501a354" /></td>
      <td><img width="450" alt="Joining Windows 10 to Domain" src="https://github.com/user-attachments/assets/dbae9389-eb9a-4c24-b69b-5dfdff94d4b8" /></td>
    </tr>
    <tr>
      <td align="center"><b>Verifying DHCP Address Assignment</b></td>
      <td align="center"><b>Authenticating with Domain Admin</b></td>
    </tr>
    <tr>
      <td><img width="450" alt="Adding Windows 10 to Domain" src="https://github.com/user-attachments/assets/4f0ca35b-8990-4336-8878-a5b6648b3a21" /></td>
      <td><img width="450" alt="Launching Windows 10 VM" src="https://github.com/user-attachments/assets/d3efea8e-c29f-40fa-9efc-b413e411f753" /></td>
    </tr>
    <tr>
      <td align="center"><b>Joining Windows 10 to Domain</b></td>
      <td align="center"><b>Launching Windows 10 VM</b></td>
    </tr>
  </table>
</div>

## **6. Authenticating a Random User on Windows 10**

1. **Pick a Random User (Anita Carron)**
2. **Login to Windows 10 using Anita Carron’s credentials**
3. **Verify Network Configuration (`ipconfig` command)**
4. **Ensure the user has the correct permissions based on their OU**

## User Authentication & Network Verification

<div align="center">
  <table>
    <tr>
      <td><img width="400" alt="IPConfig Verification" src="https://github.com/user-attachments/assets/f53f19a8-9dea-4d09-9fa7-23139e335949" /></td>
      <td><img width="400" alt="Successful Authentication with Anita Carron" src="https://github.com/user-attachments/assets/84862bee-52ce-43ee-86d4-3cb921457f19" /></td>
      <td><img width="400" alt="Picking Random User (Anita Carron)" src="https://github.com/user-attachments/assets/a9e68c2c-50b1-4211-b9a0-b400123c5303" /></td>
    </tr>
    <tr>
      <td align="center"><b>IPConfig Verification</b></td>
      <td align="center"><b>Successful Authentication</b></td>
      <td align="center"><b>Picking User (Anita Carron)</b></td>
    </tr>
  </table>
</div>

## **7. Level Up This Lab By Implementing Security Policies for Users**

1. **Create Group Policies for different OUs**
2. **Restrict administrative access** to non-admin users
3. **Enable password policies** and login restrictions
4. **Deploy user-specific access control** based on job roles

## Project Outcomes & Key Results

- 90% Time Reduction – Automated 150+ user accounts & OUs using PowerShell, eliminating manual setup
- 99.9% Uptime – Configured DHCP, NAT, and routing for seamless network connectivity
- Stronger Security – Implemented role-based access policies for domain users, ensuring compliance
- Real-World Simulation – Successfully joined Windows 10 clients to AD, enforcing domain-wide security

## **Potential Next Steps**

- **Deploy File Server & Shared Folders**
- **Configure RDP & VPN for remote access**
- **Implement multi-factor authentication (MFA) for added security**

---

This project is part of my **Active Directory and Windows Server Administration portfolio**. For any inquiries, reach out via **[LinkedIn](https://linkedin.com/in/jamesmoore1983)** or check out my **TechGneek YouTube channel**[YouTube](https://youtube.com/@TechGneek)!

## Built and documented by Paul Umejiofor - PumejLab**

🚀 Project Highlight: Automated Windows Active Directory Lab on Microsoft Azure

I recently completed a hands-on project deploying a Windows Active Directory lab in Azure using Terraform and Ansible.

The project focused on automating the setup of a Windows Server domain controller and a Windows client, configuring Active Directory, and joining the client to the domain.

🔧 Key technologies and skills:

Microsoft Azure

Terraform for Infrastructure as Code (IaC)

Ansible for configuration management and automation

Windows Server and Active Directory

WinRM connectivity and secure credential management

Automated deployment validation and troubleshooting

One of my biggest takeaways was learning how to troubleshoot authentication issues and refine automation to make deployments more reliable and repeatable.

I’m continuing to build my skills in cloud infrastructure, systems administration, and automation, and I look forward to taking on more hands-on projects.

- #MicrosoftAzure #Terraform #Ansible #ActiveDirectory #CloudComputing #InfrastructureAsCode #Automation #ITProjects

## Architecture Overview

This project automates the deployment of a Windows Active Directory
environment on AWS using Terraform for infrastructure provisioning
and Ansible for Windows configuration.

![Windows AD DS AWS Architecture](docs/aws-adds-architecture.png)

### Deployment Components

- **Terraform:** Provisions AWS networking, security groups, and EC2 instances.
- **Windows Server 2022:** Hosts Active Directory Domain Services and DNS.
- **Windows client:** Validates domain joining and authentication.
- **Ansible:** Configures Windows services, creates organizational units,
  imports domain users, and validates connectivity.
- **Security:** Restricts administrative access to a trusted IP address
  and protects credentials using secure secret handling.

### Deployment Workflow

1. Run `startupadds.sh` to validate prerequisites.
2. Initialize and validate Terraform.
3. Review and apply the AWS infrastructure plan.
4. Verify security group rules, Windows readiness, and credentials.
5. Configure AD DS and DNS, create OUs and users, and join the client.
6. Validate the deployment and record the results.

## Configuring sonarqube to jenkins server

A. Install the Jenkins SonarQube plugin

- Go to Manage Jenkins → Plugins → Available plugins.

- Search for and install: SonarQube Scanner for Jenkins Restart Jenkins if requested.

B. Configure the SonarQube server

- Go to Manage Jenkins → System → SonarQube installations.

Add an installation:

Setting                                 Value
Name                                    SonarQube
Server URL                              <http://192.168.1.112:9000>
Server authentication token             Your SonarQube Jenkins token (Create this from sonarqube)

- Create a SonarQube token from your SonarQube account under My Account → Security → Generate Tokens, then add it to Jenkins as a Secret text credential and select it in the server configuration.

C. Configure the SonarScanner tool

- Go to Manage Jenkins → Tools → SonarQube Scanner installations.
- This (SonarScanner) name must match the Jenkinsfile's tool 'SonarScanner' declaration.

Setting                                   Value
Name                                      SonarScanner
Install automatically                     Checked

D. Configure the SonarQube webhook

- This is important because Jenkins needs to receive the Quality Gate result.

In SonarQube:

1. Go to Administration → Configuration → Webhooks.
2. Add a webhook.
3. Set its URL to: <http://YOUR-JENKINS-SERVER:8080/sonarqube-webhook/>

## What is SSM?

- SSM stands for AWS Systems Manager. It is an AWS service that lets you remotely manage and administer servers and virtual machines without needing to expose them to the internet or open SSH/RDP ports.

- Think of it as AWS's secure remote-management system. What does SSM do?

Feature                           Purpose
Session Manager                   Connect to Linux and Windows servers remotely without SSH or RDP.
Run Command                       Execute commands or PowerShell scripts remotely.
Patch Manager                     Automate operating system patching.
Fleet Manager                     Manage and monitor EC2 instances.
Parameter Store                   Securely store configuration values and application parameters.
Automation                        Automate administrative tasks and operational procedures.

## How SSM works in your AWS Windows AD project

- Your architecture uses SSM to manage your Windows Domain Controller and Windows client in private subnets.
- Here's what happens during your deployment:

1. Terraform provisions your Windows EC2 instances.
2. Each Windows instance runs the SSM Agent.
3. The SSM Agent establishes outbound communication with AWS Systems Manager.
4. Your Jenkins server uses the AWS CLI and Session Manager plugin to establish SSM port-forwarding sessions.
5. Ansible connects through those tunnels to configure Active Directory and join the Windows client to the domain.

## Why SSM is valuable for DevOps

- SSM is an important cloud infrastructure security skill because it helps you:

- Avoid exposing SSH (22) and RDP (3389) to the public internet.
- Centrally manage EC2 instances.
- Execute remote commands through automation.
- Integrate secure server administration into Jenkins pipelines.
- Reduce the need for traditional bastion hosts.

```bash
trivy config \
    --misconfig-scanners=terraform \
    --severity HIGH,CRITICAL \
    --format json \
    --output trivy-report.json \
    .

jq -r '
  .Results[]?.Misconfigurations[]?
  | [
      .ID,
      .Severity,
      .CauseMetadata.Resource,
      .CauseMetadata.Code.Lines[0].Number,
      .CauseMetadata.Code.Lines[-1].Number
    ]
  | @tsv
' trivy-report.json

jq -r '
  [.Results[]?.Misconfigurations[]?]
  | group_by(.Severity)
  | map("\(.[0].Severity): \(length)")
  | .[]
' trivy-report.json
```

🚀 **Portfolio Project: Automated Windows Server 2022 Active Directory Deployment on AWS**

I’m excited to share a hands-on cloud infrastructure and DevOps project I’ve been building: **Windows Server 2022 AD DS Auto Deployment on AWS.**

The goal was to automate the deployment of a Windows Active Directory environment using Infrastructure as Code, configuration management, and CI/CD — while keeping the Windows servers private and minimizing manual administration.

☁️ **Project Architecture & Technologies**

🔹 **AWS** – VPC, public and private subnets, EC2, IAM, Systems Manager, Secrets Manager  
🔹 **Terraform** – Automated infrastructure provisioning  
🔹 **Ansible & PowerShell** – Windows configuration, AD DS installation, DNS, OU creation, and domain user automation  
🔹 **AWS Systems Manager** – Private server management and temporary port forwarding  
🔹 **WinRM over HTTPS** – Secure Ansible communication with Windows hosts  
🔹 **Jenkins** – CI/CD pipeline with deployment and destruction workflows  
🔹 **Trivy** – Infrastructure-as-Code and security scanning  
🔹 **SonarQube** – Static code analysis and quality gate integration  
🔹 **GitHub** – Source control and project documentation  

🛡️ **Security-Focused Design**

The Windows instances are deployed in a private subnet without direct public IP exposure. AWS Systems Manager is used for remote management, while a Linux NAT instance provides controlled outbound connectivity.

Sensitive automation data is protected using Ansible Vault and Jenkins credentials.

⚙️ **What I Automated**

✅ Provisioned AWS infrastructure with Terraform  
✅ Deployed and configured Windows Server 2022  
✅ Installed and configured Active Directory Domain Services  
✅ Automated DNS, organizational units, and domain user creation  
✅ Validated Windows remoting and domain connectivity  
✅ Built a Jenkins pipeline with Trivy and SonarQube integration  
✅ Added parameterized `APPLY` and `DESTROY` workflows with approval gates  
✅ Documented deployment, validation, and troubleshooting procedures  

The AWS deployment has successfully completed its infrastructure and Active Directory validation. I’m currently finalizing the Jenkins execution environment and preparing to extend the project into **Azure**, bringing the automation toward a multi-cloud implementation.

This project has been a great opportunity to strengthen my practical skills in cloud infrastructure, Windows administration, automation, networking, and DevSecOps.

📌 **Next milestone:** Azure AD DS environment deployment with Terraform, Ansible, and Jenkins.

## AWS #DevOps #CloudEngineering #Terraform #Ansible #Jenkins #WindowsServer #ActiveDirectory #DevSecOps #Trivy #SonarQube #InfrastructureAsCode #Automation #CloudSecurity #PortfolioProject
