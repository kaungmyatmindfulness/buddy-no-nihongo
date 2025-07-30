## Phase1: InfrastructureSetup&CodePreparation

### 1.1UpdateConfigurationforAWS

```go

packageconfig


import (

"context"

"encoding/json"

"fmt"

"log"


"github.com/aws/aws-sdk-go-v2/aws"

"github.com/aws/aws-sdk-go-v2/config"

"github.com/aws/aws-sdk-go-v2/service/secretsmanager"

"github.com/aws/aws-sdk-go-v2/service/ssm"

)


typeAWSConfigLoaderstruct {

secretsClient*secretsmanager.Client

ssmClient*ssm.Client

}


funcNewAWSConfigLoader() (*AWSConfigLoader, error) {

cfg, err:=config.LoadDefaultConfig(context.TODO())

iferr!=nil {

returnnil, fmt.Errorf("unable to load AWS config: %v", err)

  }


return&AWSConfigLoader{

secretsClient: secretsmanager.NewFromConfig(cfg),

ssmClient:     ssm.NewFromConfig(cfg),

  }, nil

}


func (a *AWSConfigLoader) LoadSecrets(secretNamestring) (map[string]string, error) {

result, err:=a.secretsClient.GetSecretValue(context.TODO(), &secretsmanager.GetSecretValueInput{

SecretId: aws.String(secretName),

  })

iferr!=nil {

returnnil, fmt.Errorf("failed to retrieve secret %s: %v", secretName, err)

  }


varsecretsmap[string]string

iferr:=json.Unmarshal([]byte(*result.SecretString), &secrets); err!=nil {

returnnil, fmt.Errorf("failed to parse secret JSON: %v", err)

  }


returnsecrets, nil

}


func (a *AWSConfigLoader) LoadParameter(paramNamestring) (string, error) {

result, err:=a.ssmClient.GetParameter(context.TODO(), &ssm.GetParameterInput{

Name: aws.String(paramName),

  })

iferr!=nil {

return"", fmt.Errorf("failed to retrieve parameter %s: %v", paramName, err)

  }


return*result.Parameter.Value, nil

}


// Enhanced LoadConfig function for AWS deployment

funcLoadConfigAWS() (*AppConfig, error) {

cfg:=&AppConfig{

Port:     getEnvWithDefault("PORT", "8080"),

GRPCPort: getEnvWithDefault("GRPC_PORT", "50051"),

LogLevel: getEnvWithDefault("LOG_LEVEL", "info"),

  }


// Load from AWS if running in AWS environment

ifgetEnvWithDefault("AWS_EXECUTION_ENV", "") !="" {

awsLoader, err:=NewAWSConfigLoader()

iferr!=nil {

log.Printf("Failed to initialize AWS config loader: %v", err)

returnLoadConfig() // Fallback to local config

    }


// Load secrets

secrets, err:=awsLoader.LoadSecrets("wise-owl/production")

iferr!=nil {

log.Printf("Failed to load AWS secrets: %v", err)

    } else {

cfg.Database.URI=secrets["MONGODB_URI"]

cfg.JWT.Secret=secrets["JWT_SECRET"]

cfg.Auth0.Domain=secrets["AUTH0_DOMAIN"]

cfg.Auth0.Audience=secrets["AUTH0_AUDIENCE"]

    }


// Load parameters

ifdbType, err:=awsLoader.LoadParameter("/wise-owl/DB_TYPE"); err==nil {

cfg.Database.Type=dbType

    }

  }


// Fallback to environment variables

ifcfg.Database.URI=="" {

cfg.Database.URI=getEnvWithDefault("MONGODB_URI", "mongodb://localhost:27017")

  }

ifcfg.Database.Type=="" {

cfg.Database.Type=getEnvWithDefault("DB_TYPE", "mongodb")

  }


returncfg, nil

}

```

### 1.2UpdateDatabaseConfigurationforDocumentDB

```go

packagedatabase


import (

"context"

"crypto/tls"

"fmt"

"net"


"go.mongodb.org/mongo-driver/mongo"

"go.mongodb.org/mongo-driver/mongo/options"

)


funcCreateDocumentDBConnection(uristring) (*mongo.Client, error) {

// DocumentDB requires TLS

tlsConfig:=&tls.Config{

InsecureSkipVerify: false,

  }


// Custom dialer for DocumentDB

dialer:=&net.Dialer{}


clientOptions:=options.Client().

ApplyURI(uri).

SetTLSConfig(tlsConfig).

SetDialer(dialer).

SetReplicaSet("rs0").

SetReadPreference(readpref.SecondaryPreferred())


client, err:=mongo.Connect(context.TODO(), clientOptions)

iferr!=nil {

returnnil, fmt.Errorf("failed to connect to DocumentDB: %v", err)

  }


// Test the connection

err=client.Ping(context.TODO(), nil)

iferr!=nil {

returnnil, fmt.Errorf("failed to ping DocumentDB: %v", err)

  }


returnclient, nil

}


// Enhanced CreateDatabaseSingleton for AWS DocumentDB

funcCreateDatabaseSingleton(cfg*config.AppConfig) *mongo.Database {

once.Do(func() {

varclient*mongo.Client

varerrerror


ifcfg.Database.Type=="documentdb" {

client, err=CreateDocumentDBConnection(cfg.Database.URI)

    } else {

client, err=mongo.Connect(context.TODO(), options.Client().ApplyURI(cfg.Database.URI))

    }


iferr!=nil {

log.Fatalf("Failed to connect to database: %v", err)

    }


databaseInstance=client.Database(cfg.Database.Name)

  })

returndatabaseInstance

}

```

### 1.3EnhancedHealthChecksforAWS

```go

packagehealth


import (

"context"

"fmt"

"net/http"

"time"


"github.com/gin-gonic/gin"

"go.mongodb.org/mongo-driver/mongo"

)


typeAWSHealthCheckerstruct {

*SimpleHealthChecker

db*mongo.Database

grpcServerinterface{}

}


funcNewAWSHealthChecker(serviceNamestring, db*mongo.Database) *AWSHealthChecker {

return&AWSHealthChecker{

SimpleHealthChecker: NewSimpleHealthChecker(serviceName),

db:                  db,

  }

}


func (h *AWSHealthChecker) RegisterAWSRoutes(router*gin.Engine) {

health:=router.Group("/health")

  {

health.GET("/", h.Health)

health.GET("/ready", h.ReadinessCheck)

health.GET("/live", h.LivenessCheck)

health.GET("/deep", h.DeepHealthCheck) // For ALB health checks

  }

}


func (h *AWSHealthChecker) ReadinessCheck(c*gin.Context) {

// Check if service is ready to receive traffic

checks:=map[string]bool{

"database": h.checkDatabase(),

"grpc":     h.checkGRPC(),

  }


allReady:=true

for_, ready:=rangechecks {

if!ready {

allReady=false

break

    }

  }


status:=http.StatusOK

if!allReady {

status=http.StatusServiceUnavailable

  }


c.JSON(status, gin.H{

"status": map[string]string{

"ready": fmt.Sprintf("%t", allReady),

    },

"checks": checks,

"timestamp": time.Now().UTC(),

  })

}


func (h *AWSHealthChecker) LivenessCheck(c*gin.Context) {

// Simple check if service is alive

c.JSON(http.StatusOK, gin.H{

"status": "alive",

"service": h.serviceName,

"timestamp": time.Now().UTC(),

  })

}


func (h *AWSHealthChecker) DeepHealthCheck(c*gin.Context) {

// Comprehensive health check for monitoring

checks:=map[string]interface{}{

"database": h.getDatabaseStatus(),

"memory":   h.getMemoryUsage(),

"uptime":   time.Since(h.startTime).Seconds(),

  }


c.JSON(http.StatusOK, gin.H{

"service": h.serviceName,

"status":  "healthy",

"checks":  checks,

"timestamp": time.Now().UTC(),

  })

}


func (h *AWSHealthChecker) checkDatabase() bool {

ifh.db==nil {

returnfalse

  }


ctx, cancel:=context.WithTimeout(context.Background(), 2*time.Second)

defercancel()


returnh.db.Client().Ping(ctx, nil) ==nil

}


func (h *AWSHealthChecker) getDatabaseStatus() map[string]interface{} {

ctx, cancel:=context.WithTimeout(context.Background(), 2*time.Second)

defercancel()


status:=map[string]interface{}{

"connected": false,

"latency":   0,

  }


start:=time.Now()

iferr:=h.db.Client().Ping(ctx, nil); err==nil {

status["connected"] =true

status["latency"] =time.Since(start).Milliseconds()

  }


returnstatus

}

```

## Phase2: AWSInfrastructureasCode

### 2.1TerraformConfiguration

```hcl

terraform {

required_providers {

aws= {

source="hashicorp/aws"

version="~> 5.0"

    }

  }

}


provider"aws" {

region=var.aws_region

}


# VPCandNetworking

resource"aws_vpc""wise_owl_vpc" {

cidr_block="10.0.0.0/16"

enable_dns_hostnames=true

enable_dns_support=true


tags= {

Name="wise-owl-vpc"

Environment=var.environment

  }

}


resource"aws_internet_gateway""wise_owl_igw" {

vpc_id=aws_vpc.wise_owl_vpc.id


tags= {

Name="wise-owl-igw"

  }

}


# PublicSubnetsforALB

resource"aws_subnet""public_subnets" {

count=length(var.availability_zones)

vpc_id=aws_vpc.wise_owl_vpc.id

cidr_block="10.0.${count.index + 1}.0/24"

availability_zone=var.availability_zones[count.index]

map_public_ip_on_launch=true


tags= {

Name="wise-owl-public-${count.index + 1}"

Type="Public"

  }

}


# PrivateSubnetsforECSServices

resource"aws_subnet""private_subnets" {

count=length(var.availability_zones)

vpc_id=aws_vpc.wise_owl_vpc.id

cidr_block="10.0.${count.index + 10}.0/24"

availability_zone=var.availability_zones[count.index]


tags= {

Name="wise-owl-private-${count.index + 1}"

Type="Private"

  }

}


# NATGatewayforprivatesubnets

resource"aws_eip""nat_eip" {

count=length(var.availability_zones)

domain="vpc"


tags= {

Name="wise-owl-nat-eip-${count.index + 1}"

  }

}


resource"aws_nat_gateway""nat_gateway" {

count=length(var.availability_zones)

allocation_id=aws_eip.nat_eip[count.index].id

subnet_id=aws_subnet.public_subnets[count.index].id


tags= {

Name="wise-owl-nat-${count.index + 1}"

  }

}


# RouteTables

resource"aws_route_table""public_rt" {

vpc_id=aws_vpc.wise_owl_vpc.id


route {

cidr_block="0.0.0.0/0"

gateway_id=aws_internet_gateway.wise_owl_igw.id

  }


tags= {

Name="wise-owl-public-rt"

  }

}


resource"aws_route_table""private_rt" {

count=length(var.availability_zones)

vpc_id=aws_vpc.wise_owl_vpc.id


route {

cidr_block="0.0.0.0/0"

nat_gateway_id=aws_nat_gateway.nat_gateway[count.index].id

  }


tags= {

Name="wise-owl-private-rt-${count.index + 1}"

  }

}


# RouteTableAssociations

resource"aws_route_table_association""public_rta" {

count=length(aws_subnet.public_subnets)

subnet_id=aws_subnet.public_subnets[count.index].id

route_table_id=aws_route_table.public_rt.id

}


resource"aws_route_table_association""private_rta" {

count=length(aws_subnet.private_subnets)

subnet_id=aws_subnet.private_subnets[count.index].id

route_table_id=aws_route_table.private_rt[count.index].id

}

```

### 2.2SecurityGroups

```hcl

# SecurityGroupforALB

resource"aws_security_group""alb_sg" {

name_prefix="wise-owl-alb-"

vpc_id=aws_vpc.wise_owl_vpc.id


ingress {

from_port=80

to_port=80

protocol="tcp"

cidr_blocks= ["0.0.0.0/0"]

  }


ingress {

from_port=443

to_port=443

protocol="tcp"

cidr_blocks= ["0.0.0.0/0"]

  }


egress {

from_port=0

to_port=0

protocol="-1"

cidr_blocks= ["0.0.0.0/0"]

  }


tags= {

Name="wise-owl-alb-sg"

  }

}


# SecurityGroupforECSServices

resource"aws_security_group""ecs_sg" {

name_prefix="wise-owl-ecs-"

vpc_id=aws_vpc.wise_owl_vpc.id


  # HTTPtrafficfromALB

ingress {

from_port=8080

to_port=8083

protocol="tcp"

security_groups= [aws_security_group.alb_sg.id]

  }


  # gRPCinter-servicecommunication

ingress {

from_port=50051

to_port=50053

protocol="tcp"

self=true

  }


egress {

from_port=0

to_port=0

protocol="-1"

cidr_blocks= ["0.0.0.0/0"]

  }


tags= {

Name="wise-owl-ecs-sg"

  }

}


# SecurityGroupforDocumentDB

resource"aws_security_group""documentdb_sg" {

name_prefix="wise-owl-documentdb-"

vpc_id=aws_vpc.wise_owl_vpc.id


ingress {

from_port=27017

to_port=27017

protocol="tcp"

security_groups= [aws_security_group.ecs_sg.id]

  }


tags= {

Name="wise-owl-documentdb-sg"

  }

}

```

### 2.3DocumentDBCluster

```hcl

# DocumentDBSubnetGroup

resource"aws_docdb_subnet_group""wise_owl_docdb_subnet_group" {

name="wise-owl-docdb-subnet-group"

subnet_ids=aws_subnet.private_subnets[*].id


tags= {

Name="wise-owl-docdb-subnet-group"

  }

}


# DocumentDBClusterParameterGroup

resource"aws_docdb_cluster_parameter_group""wise_owl_docdb_cluster_pg" {

family="docdb4.0"

name="wise-owl-docdb-cluster-pg"


parameter {

name="tls"

value="enabled"

  }


tags= {

Name="wise-owl-docdb-cluster-pg"

  }

}


# DocumentDBCluster

resource"aws_docdb_cluster""wise_owl_docdb_cluster" {

cluster_identifier="wise-owl-docdb-cluster"

engine="docdb"

master_username=var.docdb_username

master_password=var.docdb_password

backup_retention_period=7

preferred_backup_window="07:00-09:00"

preferred_maintenance_window="sun:05:00-sun:06:00"

skip_final_snapshot=var.environment!="production"

final_snapshot_identifier=var.environment=="production" ? "wise-owl-final-snapshot" : null


db_subnet_group_name=aws_docdb_subnet_group.wise_owl_docdb_subnet_group.name

vpc_security_group_ids= [aws_security_group.documentdb_sg.id]

db_cluster_parameter_group_name=aws_docdb_cluster_parameter_group.wise_owl_docdb_cluster_pg.name


storage_encrypted=true

kms_key_id=aws_kms_key.wise_owl_key.arn


tags= {

Name="wise-owl-docdb-cluster"

Environment=var.environment

  }

}


# DocumentDBClusterInstances

resource"aws_docdb_cluster_instance""wise_owl_docdb_cluster_instances" {

count=var.docdb_instance_count

identifier="wise-owl-docdb-instance-${count.index}"

cluster_identifier=aws_docdb_cluster.wise_owl_docdb_cluster.id

instance_class=var.docdb_instance_class


tags= {

Name="wise-owl-docdb-instance-${count.index}"

  }

}


# KMSKeyforencryption

resource"aws_kms_key""wise_owl_key" {

description="KMS key for Wise Owl encryption"

deletion_window_in_days=7


tags= {

Name="wise-owl-kms-key"

  }

}


resource"aws_kms_alias""wise_owl_key_alias" {

name="alias/wise-owl-key"

target_key_id=aws_kms_key.wise_owl_key.key_id

}

```

## Phase3: ECSandApplicationLoadBalancer

### 3.1ECRRepositories

```hcl

# ECRRepositories

resource"aws_ecr_repository""wise_owl_repos" {

for_each=toset(["users", "content", "quiz", "nginx"])


name="wise-owl-${each.key}"

image_tag_mutability="MUTABLE"


image_scanning_configuration {

scan_on_push=true

  }


encryption_configuration {

encryption_type="KMS"

kms_key=aws_kms_key.wise_owl_key.arn

  }


tags= {

Name="wise-owl-${each.key}"

Service=each.key

  }

}


# ECRLifecyclePolicies

resource"aws_ecr_lifecycle_policy""wise_owl_lifecycle" {

for_each=aws_ecr_repository.wise_owl_repos

repository=each.value.name


policy=jsonencode({

rules= [

      {

rulePriority=1

description="Keep last 30 production images"

selection= {

tagStatus="tagged"

tagPrefixList= ["v", "release"]

countType="imageCountMoreThan"

countNumber=30

        }

action= {

type="expire"

        }

      },

      {

rulePriority=2

description="Keep last 10 development images"

selection= {

tagStatus="untagged"

countType="imageCountMoreThan"

countNumber=10

        }

action= {

type="expire"

        }

      }

    ]

  })

}

```

### 3.2ECSClusterandServices

```hcl

# ECSCluster

resource"aws_ecs_cluster""wise_owl_cluster" {

name="wise-owl-cluster"


configuration {

execute_command_configuration {

kms_key_id=aws_kms_key.wise_owl_key.arn

logging="OVERRIDE"


log_configuration {

cloud_watch_encryption_enabled=true

cloud_watch_log_group_name=aws_cloudwatch_log_group.ecs_logs.name

      }

    }

  }


tags= {

Name="wise-owl-cluster"

  }

}


# CloudWatchLogGroupforECS

resource"aws_cloudwatch_log_group""ecs_logs" {

name="/ecs/wise-owl"

retention_in_days=14

kms_key_id=aws_kms_key.wise_owl_key.arn


tags= {

Name="wise-owl-ecs-logs"

  }

}


# ECSTaskExecutionRole

resource"aws_iam_role""ecs_task_execution_role" {

name="wise-owl-ecs-task-execution-role"


assume_role_policy=jsonencode({

Version="2012-10-17"

Statement= [

      {

Action="sts:AssumeRole"

Effect="Allow"

Principal= {

Service="ecs-tasks.amazonaws.com"

        }

      }

    ]

  })

}


resource"aws_iam_role_policy_attachment""ecs_task_execution_role_policy" {

role=aws_iam_role.ecs_task_execution_role.name

policy_arn="arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"

}


# ECSTaskRole (forapplicationpermissions)

resource"aws_iam_role""ecs_task_role" {

name="wise-owl-ecs-task-role"


assume_role_policy=jsonencode({

Version="2012-10-17"

Statement= [

      {

Action="sts:AssumeRole"

Effect="Allow"

Principal= {

Service="ecs-tasks.amazonaws.com"

        }

      }

    ]

  })

}


# AttachpermissionsforSecretsManagerandSystemsManager

resource"aws_iam_role_policy""ecs_task_secrets_policy" {

name="wise-owl-ecs-task-secrets-policy"

role=aws_iam_role.ecs_task_role.id


policy=jsonencode({

Version="2012-10-17"

Statement= [

      {

Effect="Allow"

Action= [

"secretsmanager:GetSecretValue",

"ssm:GetParameter",

"ssm:GetParameters",

"kms:Decrypt"

        ]

Resource= [

aws_secretsmanager_secret.wise_owl_secrets.arn,

"arn:aws:ssm:${var.aws_region}:*:parameter/wise-owl/*",

aws_kms_key.wise_owl_key.arn

        ]

      }

    ]

  })

}

```

### 3.3TaskDefinitions

```json
{
	"family": "wise-owl-users",

	"networkMode": "awsvpc",

	"requiresCompatibilities": ["FARGATE"],

	"cpu": "512",

	"memory": "1024",

	"executionRoleArn": "${execution_role_arn}",

	"taskRoleArn": "${task_role_arn}",

	"containerDefinitions": [
		{
			"name": "users-service",

			"image": "${ecr_repository_url}/wise-owl-users:${image_tag}",

			"portMappings": [
				{
					"containerPort": 8081,

					"protocol": "tcp"
				},

				{
					"containerPort": 50051,

					"protocol": "tcp"
				}
			],

			"environment": [
				{
					"name": "PORT",

					"value": "8081"
				},

				{
					"name": "GRPC_PORT",

					"value": "50051"
				},

				{
					"name": "AWS_EXECUTION_ENV",

					"value": "AWS_ECS_FARGATE"
				},

				{
					"name": "DB_TYPE",

					"value": "documentdb"
				}
			],

			"secrets": [
				{
					"name": "MONGODB_URI",

					"valueFrom": "${secrets_arn}:MONGODB_URI::"
				},

				{
					"name": "JWT_SECRET",

					"valueFrom": "${secrets_arn}:JWT_SECRET::"
				}
			],

			"logConfiguration": {
				"logDriver": "awslogs",

				"options": {
					"awslogs-group": "/ecs/wise-owl",

					"awslogs-region": "${aws_region}",

					"awslogs-stream-prefix": "users"
				}
			},

			"healthCheck": {
				"command": [
					"CMD-SHELL",

					"curl -f http://localhost:8081/health/ready || exit 1"
				],

				"interval": 30,

				"timeout": 5,

				"retries": 3,

				"startPeriod": 60
			},

			"essential": true
		}
	]
}
```

### 3.4ApplicationLoadBalancer

```hcl

# ApplicationLoadBalancer

resource"aws_lb""wise_owl_alb" {

name="wise-owl-alb"

internal=false

load_balancer_type="application"

security_groups= [aws_security_group.alb_sg.id]

subnets=aws_subnet.public_subnets[*].id


enable_deletion_protection=var.environment=="production"


tags= {

Name="wise-owl-alb"

Environment=var.environment

  }

}


# TargetGroupsforeachservice

resource"aws_lb_target_group""service_targets" {

for_each= {

users= { port=8081, path="/api/v1/users/health/ready" }

content= { port=8082, path="/api/v1/content/health/ready" }

quiz= { port=8083, path="/api/v1/quiz/health/ready" }

  }


name="wise-owl-${each.key}-tg"

port=each.value.port

protocol="HTTP"

vpc_id=aws_vpc.wise_owl_vpc.id

target_type="ip"


health_check {

enabled=true

healthy_threshold=2

interval=30

matcher="200"

path=each.value.path

port="traffic-port"

protocol="HTTP"

timeout=5

unhealthy_threshold=3

  }


depends_on= [aws_lb.wise_owl_alb]


tags= {

Name="wise-owl-${each.key}-tg"

Service=each.key

  }

}


# ALBListener (HTTP-redirectstoHTTPS)

resource"aws_lb_listener""wise_owl_http" {

load_balancer_arn=aws_lb.wise_owl_alb.arn

port="80"

protocol="HTTP"


default_action {

type="redirect"


redirect {

port="443"

protocol="HTTPS"

status_code="HTTP_301"

    }

  }

}


# ALBListener (HTTPS)

resource"aws_lb_listener""wise_owl_https" {

load_balancer_arn=aws_lb.wise_owl_alb.arn

port="443"

protocol="HTTPS"

ssl_policy="ELBSecurityPolicy-TLS-1-2-2017-01"

certificate_arn=aws_acm_certificate_validation.cert_validation.certificate_arn


  # Defaultaction-return404

default_action {

type="fixed-response"


fixed_response {

content_type="text/plain"

message_body="Service not found"

status_code="404"

    }

  }

}


# ALBListenerRulesforservicerouting

resource"aws_lb_listener_rule""service_routing" {

for_each=aws_lb_target_group.service_targets


listener_arn=aws_lb_listener.wise_owl_https.arn

priority=100+index(keys(aws_lb_target_group.service_targets), each.key)


action {

type="forward"

target_group_arn=each.value.arn

  }


condition {

path_pattern {

values= ["/api/v1/${each.key}/*"]

    }

  }

}

```

## Phase4: SecretsManagementandSSL

### 4.1AWSSecretsManager

```hcl

# SecretsManagerforsensitiveconfiguration

resource"aws_secretsmanager_secret""wise_owl_secrets" {

name="wise-owl/production"

description="Wise Owl production secrets"

kms_key_id=aws_kms_key.wise_owl_key.arn

recovery_window_in_days=var.environment=="production" ? 30 : 0


tags= {

Name="wise-owl-secrets"

Environment=var.environment

  }

}


resource"aws_secretsmanager_secret_version""wise_owl_secrets" {

secret_id=aws_secretsmanager_secret.wise_owl_secrets.id

secret_string=jsonencode({

MONGODB_URI="mongodb://${var.docdb_username}:${var.docdb_password}@${aws_docdb_cluster.wise_owl_docdb_cluster.endpoint}:27017/?ssl=true&replicaSet=rs0&readPreference=secondaryPreferred"

JWT_SECRET=var.jwt_secret

AUTH0_DOMAIN=var.auth0_domain

AUTH0_AUDIENCE=var.auth0_audience

  })

}


# SystemsManagerParametersfornon-sensitiveconfig

resource"aws_ssm_parameter""wise_owl_params" {

for_each= {

DB_TYPE="documentdb"

LOG_LEVEL=var.log_level

ENVIRONMENT=var.environment

  }


name="/wise-owl/${each.key}"

type="String"

value=each.value


tags= {

Name="wise-owl-${each.key}"

Environment=var.environment

  }

}

```

### 4.2SSLCertificatewithACM

```hcl

# RequestSSLcertificate

resource"aws_acm_certificate""wise_owl_cert" {

domain_name=var.domain_name

subject_alternative_names= ["*.${var.domain_name}"]

validation_method="DNS"


lifecycle {

create_before_destroy=true

  }


tags= {

Name="wise-owl-ssl-cert"

  }

}


# Route53DNSvalidation

resource"aws_route53_record""cert_validation" {

for_each= {

fordvoinaws_acm_certificate.wise_owl_cert.domain_validation_options : dvo.domain_name=> {

name=dvo.resource_record_name

record=dvo.resource_record_value

type=dvo.resource_record_type

    }

  }


allow_overwrite=true

name=each.value.name

records= [each.value.record]

ttl=60

type=each.value.type

zone_id=aws_route53_zone.wise_owl_zone.zone_id

}


resource"aws_acm_certificate_validation""cert_validation" {

certificate_arn=aws_acm_certificate.wise_owl_cert.arn

validation_record_fqdns= [forrecordinaws_route53_record.cert_validation : record.fqdn]

}

```

### 4.3Route53DNS

```hcl

# Route53HostedZone

resource"aws_route53_zone""wise_owl_zone" {

name=var.domain_name


tags= {

Name="wise-owl-zone"

  }

}


# ArecordpointingtoALB

resource"aws_route53_record""wise_owl_a" {

zone_id=aws_route53_zone.wise_owl_zone.zone_id

name=var.domain_name

type="A"


alias {

name=aws_lb.wise_owl_alb.dns_name

zone_id=aws_lb.wise_owl_alb.zone_id

evaluate_target_health=true

  }

}


# AAAArecordforIPv6

resource"aws_route53_record""wise_owl_aaaa" {

zone_id=aws_route53_zone.wise_owl_zone.zone_id

name=var.domain_name

type="AAAA"


alias {

name=aws_lb.wise_owl_alb.dns_name

zone_id=aws_lb.wise_owl_alb.zone_id

evaluate_target_health=true

  }

}


# Healthchecksformonitoring

resource"aws_route53_health_check""wise_owl_health" {

fqdn=var.domain_name

port=443

type="HTTPS"

resource_path="/api/v1/users/health"

failure_threshold="3"

request_interval="30"

cloudwatch_alarm_region=var.aws_region

cloudwatch_alarm_name=aws_cloudwatch_metric_alarm.alb_health.alarm_name

insufficient_data_health_status="Failure"


tags= {

Name="wise-owl-health-check"

  }

}

```

## Phase5: CloudWatchMonitoring

### 5.1CloudWatchConfiguration

```hcl

# CloudWatchDashboard

resource"aws_cloudwatch_dashboard""wise_owl_dashboard" {

dashboard_name="WiseOwl-Production"


dashboard_body=jsonencode({

widgets= [

      {

type="metric"

x=0

y=0

width=12

height=6


properties= {

metrics= [

            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.wise_owl_alb.arn_suffix],

            [".", "TargetResponseTime", ".", "."],

            [".", "HTTPCode_Target_4XX_Count", ".", "."],

            [".", "HTTPCode_Target_5XX_Count", ".", "."]

          ]

view="timeSeries"

stacked=false

region=var.aws_region

title="ALB Metrics"

period=300

        }

      },

      {

type="metric"

x=0

y=6

width=12

height=6


properties= {

metrics= [

            ["AWS/ECS", "CPUUtilization", "ServiceName", "wise-owl-users", "ClusterName", aws_ecs_cluster.wise_owl_cluster.name],

            [".", "MemoryUtilization", ".", ".", ".", "."],

            [".", "CPUUtilization", "ServiceName", "wise-owl-content", "ClusterName", aws_ecs_cluster.wise_owl_cluster.name],

            [".", "MemoryUtilization", ".", ".", ".", "."],

            [".", "CPUUtilization", "ServiceName", "wise-owl-quiz", "ClusterName", aws_ecs_cluster.wise_owl_cluster.name],

            [".", "MemoryUtilization", ".", ".", ".", "."]

          ]

view="timeSeries"

stacked=false

region=var.aws_region

title="ECS Service Metrics"

period=300

        }

      }

    ]

  })

}


# CloudWatchAlarms

resource"aws_cloudwatch_metric_alarm""alb_health" {

alarm_name="wise-owl-alb-unhealthy-targets"

comparison_operator="GreaterThanThreshold"

evaluation_periods="2"

metric_name="UnHealthyHostCount"

namespace="AWS/ApplicationELB"

period="60"

statistic="Average"

threshold="0"

alarm_description="This metric monitors ALB unhealthy targets"

alarm_actions= [aws_sns_topic.alerts.arn]


dimensions= {

LoadBalancer=aws_lb.wise_owl_alb.arn_suffix

  }

}


resource"aws_cloudwatch_metric_alarm""ecs_cpu_high" {

for_each=toset(["users", "content", "quiz"])


alarm_name="wise-owl-${each.key}-cpu-high"

comparison_operator="GreaterThanThreshold"

evaluation_periods="2"

metric_name="CPUUtilization"

namespace="AWS/ECS"

period="300"

statistic="Average"

threshold="80"

alarm_description="This metric monitors ECS ${each.key} service CPU utilization"

alarm_actions= [aws_sns_topic.alerts.arn]


dimensions= {

ServiceName="wise-owl-${each.key}"

ClusterName=aws_ecs_cluster.wise_owl_cluster.name

  }

}


# SNSTopicforalerts

resource"aws_sns_topic""alerts" {

name="wise-owl-alerts"


tags= {

Name="wise-owl-alerts"

  }

}

```

## Phase6: CI/CDwithAWSCodeDeploy

### 6.1UpdatedGitHubActionsforAWS

```yaml

name: DeploytoAWS


on:

push:

branches: [main]

workflow_dispatch:


env:

AWS_REGION: us-east-1

ECR_REGISTRY: ${{ secrets.AWS_ACCOUNT_ID }}.dkr.ecr.${{ secrets.AWS_REGION }}.amazonaws.com


jobs:

build-and-deploy:

runs-on: ubuntu-latest


steps:

-name: Checkoutcode

uses: actions/checkout@v4


-name: ConfigureAWScredentials

uses: aws-actions/configure-aws-credentials@v4

with:

aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}

aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}

aws-region: ${{ env.AWS_REGION }}


-name: LogintoAmazonECR

id: login-ecr

uses: aws-actions/amazon-ecr-login@v2


-name: BuildandpushDockerimages

run: |

        # Buildproductionimages

dockerbuild-twise-owl-users:latest-fservices/users/Dockerfile .

dockerbuild-twise-owl-content:latest-fservices/content/Dockerfile .

dockerbuild-twise-owl-quiz:latest-fservices/quiz/Dockerfile .

dockerbuild-twise-owl-nginx:latest-fnginx/Dockerfile.prodnginx/


        # TagandpushtoECR

forserviceinuserscontentquiznginx; do

dockertagwise-owl-$service:latest $ECR_REGISTRY/wise-owl-$service:$GITHUB_SHA

dockertagwise-owl-$service:latest $ECR_REGISTRY/wise-owl-$service:latest

dockerpush $ECR_REGISTRY/wise-owl-$service:$GITHUB_SHA

dockerpush $ECR_REGISTRY/wise-owl-$service:latest

done


-name: UpdateECSservices

run: |

        # Updatetaskdefinitionswithnewimagetags

forserviceinuserscontentquiz; do

awsecsupdate-service \

--clusterwise-owl-cluster \

--servicewise-owl-$service \

--force-new-deployment

done


-name: Waitfordeploymentcompletion

run: |

forserviceinuserscontentquiz; do

awsecswaitservices-stable \

--clusterwise-owl-cluster \

--serviceswise-owl-$service

done


-name: Notifydeploymentstatus

if: always()

run: |

if [ ${{ job.status }} =='success' ]; then

echo"✅ Deployment successful"

else

echo"❌ Deployment failed"

fi

```

### 6.2CodeDeployConfiguration

```yaml
version: 0.0

os: linux

hooks:

BeforeInstall:
  -location: scripts/install_dependencies.sh

  timeout: 300

  runas: root

  ApplicationStart:
    -location: scripts/start_application.sh

    timeout: 300

    runas: root

    ApplicationStop:
      -location: scripts/stop_application.sh

      timeout: 300

      runas: root

      ValidateService:
        -location: scripts/validate_service.sh

        timeout: 300
```

## Phase7: DeploymentScripts

### 7.1InfrastructureDeploymentScript

```bash

#!/bin/bash


set-e


# Configuration

AWS_REGION="${AWS_REGION:-us-east-1}"

ENVIRONMENT="${ENVIRONMENT:-production}"

DOMAIN_NAME="${DOMAIN_NAME:-your-domain.com}"


echo"🚀 Starting AWS deployment for Wise Owl..."


# Validateprerequisites

if!command-vterraform&>/dev/null; then

echo"❌ Terraform is required but not installed"

exit1

fi


if!command-vaws&>/dev/null; then

echo"❌ AWS CLI is required but not installed"

exit1

fi


# CheckAWScredentials

if!awsstsget-caller-identity&>/dev/null; then

echo"❌ AWS credentials not configured"

exit1

fi


echo"✅ Prerequisites validated"


# DeployinfrastructurewithTerraform

cddeployment/aws/terraform


echo"📦 Initializing Terraform..."

terraforminit


echo"📋 Planning infrastructure changes..."

terraformplan \

-var="environment=$ENVIRONMENT" \

-var="aws_region=$AWS_REGION" \

-var="domain_name=$DOMAIN_NAME" \

-out=tfplan


echo"🏗️ Applying infrastructure changes..."

terraformapplytfplan


# Getoutputs

ECR_REGISTRY=$(terraformoutput-rawecr_registry)

CLUSTER_NAME=$(terraformoutput-rawcluster_name)


echo"✅ Infrastructure deployed successfully"


# BuildandpushDockerimages

echo"🐳 Building and pushing Docker images..."


# LogintoECR

awsecrget-login-password--region $AWS_REGION| \

dockerlogin--usernameAWS--password-stdin $ECR_REGISTRY


# Buildproductionimages

echo"Building services..."

dockerbuild-twise-owl-users:latest-f ../../../services/users/Dockerfile ../../../

dockerbuild-twise-owl-content:latest-f ../../../services/content/Dockerfile ../../../

dockerbuild-twise-owl-quiz:latest-f ../../../services/quiz/Dockerfile ../../../


# Tagandpushimages

forserviceinuserscontentquiz; do

echo"Pushing $service service..."

dockertagwise-owl-$service:latest $ECR_REGISTRY/wise-owl-$service:latest

dockerpush $ECR_REGISTRY/wise-owl-$service:latest

done


echo"✅ Docker images pushed successfully"


# DeployECSservices

echo"🚀 Deploying ECS services..."


# Registertaskdefinitionsandcreateservices

forserviceinuserscontentquiz; do

echo"Deploying $service service..."


    # CreateECSserviceifitdoesn't exist

    if ! aws ecs describe-services \

        --cluster $CLUSTER_NAME \

        --services wise-owl-$service \

        --region $AWS_REGION &> /dev/null; then


        aws ecs create-service \

            --cluster $CLUSTER_NAME \

            --service-name wise-owl-$service \

            --task-definition wise-owl-$service \

            --desired-count 2 \

            --launch-type FARGATE \

            --network-configuration "awsvpcConfiguration={subnets=[$(terraform output -raw private_subnet_ids | tr ',' '')],securityGroups=[$(terraform output -raw ecs_security_group_id)],assignPublicIp=DISABLED}" \

            --load-balancers "targetGroupArn=$(terraform output -raw ${service}_target_group_arn),containerName=${service}-service,containerPort=808$((${service} == 'users' ? 1 : ${service} == 'content' ? 2 : 3))" \

            --region $AWS_REGION

    else

        # Update existing service

        aws ecs update-service \

            --cluster $CLUSTER_NAME \

            --service wise-owl-$service \

            --force-new-deployment \

            --region $AWS_REGION

    fi

done


echo "⏳ Waiting for services to stabilize..."

for service in users content quiz; do

    aws ecs wait services-stable \

        --cluster $CLUSTER_NAME \

        --services wise-owl-$service \

        --region $AWS_REGION

done


echo "✅ ECS services deployed successfully"


# Validate deployment

echo "🔍 Validating deployment..."

ALB_DNS=$(terraform output -raw alb_dns_name)


for service in users content quiz; do

    if curl -f -s "http://$ALB_DNS/api/v1/$service/health" > /dev/null; then

        echo "✅ $service service is healthy"

    else

        echo "❌ $service service health check failed"

        exit 1

    fi

done


echo "🎉 Deployment completed successfully!"

echo "🌐 Application available at: https://$DOMAIN_NAME"

echo "📊 Monitoring dashboard: https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:name=WiseOwl-Production"


cd - > /dev/null

```

### 7.2 Environment-specific variables

```hcl

variable "aws_region" {

  description = "AWS region"

  type        = string

  default     = "us-east-1"

}


variable "environment" {

  description = "Environment name"

  type        = string

  default     = "production"

}


variable "domain_name" {

  description = "Domain name for the application"

  type        = string

}


variable "availability_zones" {

  description = "Availability zones"

  type        = list(string)

  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]

}


variable "docdb_username" {

  description = "DocumentDB master username"

  type        = string

  default     = "wiseowl"

  sensitive   = true

}


variable "docdb_password" {

  description = "DocumentDB master password"

  type        = string

  sensitive   = true

}


variable "docdb_instance_class" {

  description = "DocumentDB instance class"

  type        = string

  default     = "db.t3.medium"

}


variable "docdb_instance_count" {

  description = "Number of DocumentDB instances"

  type        = number

  default     = 2

}


variable "jwt_secret" {

  description = "JWT secret for authentication"

  type        = string

  sensitive   = true

}


variable "auth0_domain" {

  description = "Auth0 domain"

  type        = string

  default     = ""

}


variable "auth0_audience" {

  description = "Auth0 audience"

  type        = string

  default     = ""

}


variable "log_level" {

  description = "Application log level"

  type        = string

  default     = "info"

}

```

## Deployment Timeline & Cost Estimates

### **Phase Timeline (Estimated)**

- **Phase 1-2**: Infrastructure setup (2-3 days)
- **Phase 3-4**: ECS and ALB configuration (2-3 days)
- **Phase 5-6**: Monitoring and CI/CD (1-2 days)
- **Phase 7**: Testing and optimization (1-2 days)

### **Monthly Cost Estimates**

- **DocumentDB**: $200-400 (as noted in your docs)
- **ECS Fargate**: $100-200 (3 services, 2 instances each)
- **ALB**: $20-30
- **Route 53**: $1-5
- **CloudWatch**: $10-20
- **Other services**: $20-50

**Total**: ~$350-700/month depending on traffic and instance sizes.

This plan leverages your existing microservices architecture and follows AWS best practices for production deployments. The infrastructure is designed to be scalable, secure, and cost-effective while maintaining the development workflow you'vealreadyestablished.

Similarcodefoundwith3licensetypes
