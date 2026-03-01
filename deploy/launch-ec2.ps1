# ============================================================
#  launch-ec2.ps1
#  Run this script from your local PowerShell to:
#  1. Reconfigure AWS CLI with your personal credentials
#  2. Create a key pair, security group, and EC2 instance
#  3. Print your public IP when done
#
#  Prerequisites: AWS CLI installed
#  Run: .\deploy\launch-ec2.ps1
# ============================================================

param(
    [string]$Region = "eu-north-1",
    [string]$InstanceType = "t3.large",
    [string]$KeyName = "microservices-key-v2"
)

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Java Spring Microservices - AWS EC2 Launcher" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

# --- Step 1: Reconfigure AWS CLI -----------------------------
Write-Host "`n[1/5] Checking AWS CLI Configuration..." -ForegroundColor Yellow
try {
    aws sts get-caller-identity --query "Account" --output text | Out-Null
    Write-Host "  AWS CLI is already configured. Skipping 'aws configure'." -ForegroundColor Green
} catch {
    Write-Host "  AWS CLI not configured or credentials invalid. Prompting..." -ForegroundColor Gray
    aws configure
}

# --- Step 2: Create Key Pair ---------------------------------
Write-Host "`n[2/5] Creating EC2 Key Pair '$KeyName'..." -ForegroundColor Yellow
$keyFile = "$KeyName.pem"

try {
    $keyMaterial = $(aws ec2 create-key-pair --key-name $KeyName --query "KeyMaterial" --output text --region $Region)
    if ($keyMaterial) {
        $keyMaterial | Out-File -Encoding ascii $keyFile
        Write-Host "  Key saved to: $keyFile" -ForegroundColor Green
    } else {
        Write-Host "  Key pair '$KeyName' may already exist - skipping." -ForegroundColor Gray
    }
} catch {
    Write-Host "  Key pair '$KeyName' may already exist - skipping." -ForegroundColor Gray
}

# --- Step 3: Create Security Group ---------------------------
Write-Host "`n[3/5] Creating Security Group..." -ForegroundColor Yellow

$sgName = "microservices-sg-$(Get-Random -Maximum 9999)"
$sgId = $(aws ec2 create-security-group --group-name $sgName --description "Microservices Demo Security Group" --region $Region --query "GroupId" --output text).Trim()

Write-Host "  Security Group ID: $sgId" -ForegroundColor Green

if ([string]::IsNullOrWhiteSpace($sgId)) {
    Write-Host "  ERROR: Failed to create Security Group. Check your AWS credentials." -ForegroundColor Red
    exit
}

# Open port 22 (SSH) and 4004 (API Gateway)
aws ec2 authorize-security-group-ingress --group-id $sgId --protocol tcp --port 22   --cidr 0.0.0.0/0 --region $Region | Out-Null
aws ec2 authorize-security-group-ingress --group-id $sgId --protocol tcp --port 4004 --cidr 0.0.0.0/0 --region $Region | Out-Null
aws ec2 authorize-security-group-ingress --group-id $sgId --protocol tcp --port 4005 --cidr 0.0.0.0/0 --region $Region | Out-Null
aws ec2 authorize-security-group-ingress --group-id $sgId --protocol tcp --port 4000 --cidr 0.0.0.0/0 --region $Region | Out-Null

Write-Host "  Ports 22, 4000, 4004, 4005 opened." -ForegroundColor Green

# --- Step 4: Get latest Amazon Linux 2023 AMI ----------------
Write-Host "`n[4/5] Looking up Amazon Linux 2023 AMI..." -ForegroundColor Yellow

$amiId = $(aws ec2 describe-images --owners amazon --filters "Name=name,Values=al2023-ami-2023*-x86_64" "Name=state,Values=available" --query "sort_by(Images, &CreationDate)[-1].ImageId" --output text --region $Region).Trim()

Write-Host "  AMI: $amiId" -ForegroundColor Green

if ([string]::IsNullOrWhiteSpace($amiId)) {
    Write-Host "  ERROR: Failed to find AMI. Check your internet connection or AWS region." -ForegroundColor Red
    exit
}

# --- Step 5: Launch EC2 Instance -----------------------------
Write-Host "`n[5/5] Launching EC2 $InstanceType instance..." -ForegroundColor Yellow

# Use fileb:// to pass the script directly to AWS CLI, avoiding double base64 encoding
$scriptPath = Join-Path $PSScriptRoot "ec2-bootstrap.sh"
$userDataParam = "fileb://$scriptPath"

$instanceId = $(aws ec2 run-instances --image-id $amiId --instance-type $InstanceType --key-name $KeyName --security-group-ids $sgId --user-data $userDataParam --count 1 --region $Region --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=microservices-demo}]" --query "Instances[0].InstanceId" --output text).Trim()

Write-Host "  Instance ID: $instanceId" -ForegroundColor Green
Write-Host "  Waiting for instance to get a public IP (60-90 seconds)..." -ForegroundColor Gray

if ([string]::IsNullOrWhiteSpace($instanceId)) {
    Write-Host "  ERROR: Failed to launch EC2 instance." -ForegroundColor Red
    exit
}

# Wait for the instance to be running
aws ec2 wait instance-running --instance-ids $instanceId --region $Region | Out-Null

# Get public IP
$publicIp = $(aws ec2 describe-instances --instance-ids $instanceId --query "Reservations[0].Instances[0].PublicIpAddress" --output text --region $Region).Trim()

Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host " DONE! Instance is launching." -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host " Public IP:     $publicIp" -ForegroundColor White
Write-Host " Instance ID:   $instanceId" -ForegroundColor White
Write-Host " Key File:      $keyFile" -ForegroundColor White
Write-Host ""
Write-Host " Wait 8-12 minutes for Java services to build & start." -ForegroundColor Yellow
Write-Host ""
Write-Host " Then test your API Gateway:" -ForegroundColor Cyan
Write-Host "   http://$publicIp`:4004" -ForegroundColor White
Write-Host ""
Write-Host " To SSH in and watch logs:" -ForegroundColor Cyan
Write-Host "   ssh -i $keyFile -o StrictHostKeyChecking=no ec2-user@$publicIp" -ForegroundColor White
Write-Host "   docker-compose -f /home/ec2-user/app/docker-compose.yml logs -f" -ForegroundColor White
Write-Host ""
Write-Host " To TERMINATE after presentation:" -ForegroundColor Red
Write-Host "   aws ec2 terminate-instances --instance-ids $instanceId --region $Region" -ForegroundColor White
Write-Host ""

# Save instance info to a file for easy reference
@"
INSTANCE_ID=$instanceId
PUBLIC_IP=$publicIp
REGION=$Region
KEY_FILE=$keyFile
SECURITY_GROUP=$sgId
"@ | Out-File -Encoding ascii "deploy\instance-info.txt"

Write-Host " Instance info saved to deploy\instance-info.txt" -ForegroundColor Gray
