Setup for experimenting with Amazon VPC Traffic Mirroring.

**Table of Contents**
1. [Introduction](#introduction)
2. [Prerequisites](#prerequisites)
3. [Deployment](#deployment)
   1. [Sample Service](#sample-service)
   2. [Target Instance](#target-instance)
   3. [VPC Mirroring](#vpc-mirroring)
4. [Analyzing and Capturing Mirrored Traffic](#analyzing-and-capturing-mirrored-traffic)
5. [Additional Features](#additional-features)
   1. [HTTPS Listener for Sample Service
](#https-listener-for-sample-service)
   2. [Mirror Filters for Application Load Balancers
](#mirror-filters-for-application-load-balancers)
6. [Cleanup](#cleanup)
7. [Sources, References & Additional Material](#sources-references-&-additional-material)

## Introduction

This repository contains a setup for experimenting with Amazon VPC Traffic Mirroring.

Amazon VPC Traffic Mirroring allows you to mirror network traffic from an Elastic Network Interface (ENI) to another ENI (or a Network Load Balancer). See [AWS Documentation](https://docs.aws.amazon.com/vpc/latest/mirroring/what-is-traffic-mirroring.html) for additional information.

**Note**: Amazon VPC Traffic Mirroring supports ENIs of instances running on top of the AWS Nitro System (e.g. t3, m5, c5 and r5 instances). You cannot mirror traffic from an ENI that is attached to a non-Nitro instance.

The repository contains the following components (or CloudFormation stacks):

* `vpc-mirroring-sample-service` - Sample service with a public ALB routing traffic to a Fargate backend for testing mirroring.
* `vpc-mirroring-target-instance` - EC2 instance for receiving mirrored network traffic.
* `vpc-mirroring` - Amazon VPC Traffic Mirroring configuration.

## Prerequisites

The setup in this repository has the following requirements:

* AWS CLI with admin-level credentials (needs to be able to deploy IAM roles).
* VPC & Subnet stacks from [sjakthol/aws-account-infra](https://github.com/sjakthol/aws-account-infra).

Also, the `Makefile` is optimized for deployments made on `eu-west-1` and `eu-north-1` regions (but should work with other regions as well).

## Deployment

### Sample Service

Deploy the sample service stack by running

```bash
make deploy-vpc-mirroring-sample-service
```

Once complete, you can find the ALB address from the stack outputs.

**Note**: This stack is optional. You can use this stack as a sample traffic mirror source if you don't have other services to mirror.

### Target Instance

Deploy the target instance stack by running

```bash
make deploy-vpc-mirroring-target-instance
```

Once complete, you can use AWS Systems Manager Session Manager (SSM) to access the EC2 instance that receives the mirrored network traffic.

### VPC Mirroring

You'll need to make the following changes to the stack template prior to deployment:

* Find the ID of the ENI you would like to monitor and enter it to the `Default` field of `SourceEni` parameter.
* Find the ID of the ENI of the target instance and enter it into the `Default` field of `TargetEni` parameter.

Once done, you can deploy the VPC Traffic Mirroring configuration by running

```bash
make deploy-vpc-mirroring
```

## Analyzing and Capturing Mirrored Traffic

Once the stacks have been deployed, Amazon VPC starts to mirror traffic from the source ENI into the ENI of the target instance. To get started, log in to the target instance with Amazon SSM Session Manager.

Amazon VPC mirrors the traffic from the source ENI into the target ENI port 4789 over UDP. Amazon VPC encapsulates the traffic with a VXLAN header. You can use the following commands to create a new VXLAN interface to receive the mirrored traffic ([reference](https://cloudshark.io/articles/aws-vpc-traffic-mirroring-cloud-packet-capture/)):

```
# ip link add capture0 type vxlan id 12345 local 10.0.0.83 remote 10.0.0.84 dev eth0 dstport 4789
# ip link set capture0 up
```

These commands create a new network interface, `capture0`, that receives traffic sent to `eth0` port `4789` with VXLAN ID `12345`. The VXLAN ID must match the `VirtualNetworkId` defined in the mirror session configuration (`MirrorSession` of `vpc-mirroring` stack; set to `12345` unless changed).

You can now run `tcpdump` to see the mirrored traffic:

```
# tcpdump -n -i capture0 -vv
```

## Additional Features

### HTTPS Listener for Sample Service

The sample service is available via HTTP by default. If you wish to have a HTTPS endpoint, you'll need to have an ACM certificate.

If you have a certificate, open `vpc-mirroring-sample-service.yaml` template, place the ARN of the ACM Certificate to the `CertificateArn` field of the `AlbHttpsListener` resource and uncomment the resource to deploy a HTTPS Listener.

If you don't have a certificate, you can create and upload a self-signed one to ACM as follows:

```bash
# Generate the certificate (from https://stackoverflow.com/a/41366949)
openssl req -x509 \
  -newkey rsa:2048\
  -sha256 \
  -days 3650 \
  -nodes \
  -keyout certificates/example.key \
  -out certificates/example.crt \
  -subj "/CN=example.com" \
  -addext "subjectAltName=DNS:example.com,DNS:example.net"

# Upload certificate to ACM
aws acm import-certificate \
  --certificate file://certificates/example.crt \
  --private-key file://certificates/example.key \
  --tags Key=Name,Value=example.com-cert
```

Once done, take a note of the ACM Certificate ARN and change the stack template as instructed above.

### Mirror Filters for Application Load Balancers

Amazon VPC Traffic Mirroring can mirror traffic from ENIs of some Application Load Balancers (ALB). Amazon VPC Traffic Mirroring only supports instances that are built on the AWS Nitro System. You can mirror the traffic of an ALB if it uses a supported instance. ALBs are more likely to support mirroring on newer regions (like `eu-north-1`) that do not have non-Nitro based previous generation instances available. If the ALB is not using a supported instance, you cannot mirror its traffic.

For supported ALBs, the VPC Mirroring template includes two mirror filters to mirror a portion of the ALB network traffic:

* `MirrorAlbClientTraffic` - Mirrors all ingress and egress traffic between clients and the ALB. Traffic between the ALB and targets is not mirrored.
* `MirrorAlbTargetTraffic` - Mirrors all ingress and egress traffic between the ALB and its targets. Traffic between clients and the ALB is not mirrored.

These filters can be used to, for example, debug Client TLS Negotiation Errors between clients and the ALB. Previously, ALB has not provided any details on the errors apart from a single metric in CloudWatch. With VPC Mirroring, you can mirror the packets between the clients and the ALB, and record failing TLS negotiations to determine why the errors occur.

**Note**: The filters work best with `internet-facing` ALBs. They do not capture traffic for `internal` ALBs correctly if the clients and the targets are in the same VPC. If you wish to use the filters for this scenario, you'll need to make the `DestinationCidrBlock` and `SourceCidrBlock` that refer the VPC CIDR to be more specific (i.e. to only match clients or targets in different subnets).

## Cleanup

Execute the following commands to clean up AWS resources:

```
make delete-vpc-mirroring-sample-service
make delete-vpc-mirroring-target-instance
make delete-vpc-mirroring
```

## Sources, References & Additional Material

* [AWS Documentation](https://docs.aws.amazon.com/vpc/latest/mirroring/what-is-traffic-mirroring.html), AWS
* [Troubleshooting AWS Environments Using Packet Captures](https://cloudshark.io/articles/aws-vpc-traffic-mirroring-cloud-packet-capture/), CloudShark
