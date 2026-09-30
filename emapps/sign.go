// Copyright (c) Chemsource Studio. All rights reserved.
// CsAC eMApps - RSA signature engine

package main

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"os"
	"path/filepath"
)

const (
	rsaKeyBits  = 2048
	privKeyFile = "emapps_rsa.pem"
	pubKeyFile  = "emapps_rsa.pub"
)

// signer RSA 签名管理器（轻量级，仅依赖标准库 crypto/*）
type signer struct {
	privateKey *rsa.PrivateKey
	publicKey  *rsa.PublicKey
	publicPEM  []byte
}

func newSigner() *signer {
	return &signer{}
}

// init 初始化密钥对（不存在时自动生成 2048-bit RSA）
func (s *signer) init() error {
	if err := os.MkdirAll("keys", 0700); err != nil {
		return err
	}
	privPath := filepath.Join("keys", privKeyFile)
	pubPath := filepath.Join("keys", pubKeyFile)

	// 加载已有密钥
	if data, err := os.ReadFile(privPath); err == nil {
		block, _ := pem.Decode(data)
		if block == nil || block.Type != "RSA PRIVATE KEY" {
			goto generate
		}
		priv, err := x509.ParsePKCS1PrivateKey(block.Bytes)
		if err != nil {
			goto generate
		}
		s.privateKey = priv
		s.publicKey = &priv.PublicKey
		if pubPEM, err := os.ReadFile(pubPath); err == nil {
			s.publicPEM = pubPEM
		}
		return nil
	}

generate:
	// 生成新密钥对
	priv, err := rsa.GenerateKey(rand.Reader, rsaKeyBits)
	if err != nil {
		return fmt.Errorf("RSA 密钥生成失败: %w", err)
	}
	s.privateKey = priv
	s.publicKey = &priv.PublicKey

	// 保存私钥
	privPEM := pem.EncodeToMemory(&pem.Block{
		Type:  "RSA PRIVATE KEY",
		Bytes: x509.MarshalPKCS1PrivateKey(priv),
	})
	if err := os.WriteFile(privPath, privPEM, 0600); err != nil {
		return err
	}

	// 保存公钥（PEM，供客户端嵌入验证）
	pubPEM := pem.EncodeToMemory(&pem.Block{
		Type:  "RSA PUBLIC KEY",
		Bytes: x509.MarshalPKCS1PublicKey(&priv.PublicKey),
	})
	s.publicPEM = pubPEM
	if err := os.WriteFile(pubPath, pubPEM, 0644); err != nil {
		return err
	}

	return nil
}

// Sign 对数据进行 RSA-SHA256 签名，返回 base64 字符串
func (s *signer) Sign(data []byte) (string, error) {
	hash := sha256.Sum256(data)
	sig, err := rsa.SignPKCS1v15(rand.Reader, s.privateKey, crypto.SHA256, hash[:])
	if err != nil {
		return "", fmt.Errorf("签名失败: %w", err)
	}
	return base64.StdEncoding.EncodeToString(sig), nil
}

// SignPkg 对包文件计算 SHA-256 摘要并签名
// 返回 hex 摘要和 base64 签名
func (s *signer) SignPkg(pkgData []byte) (hashHex, signatureB64 string, err error) {
	h := sha256.Sum256(pkgData)
	hashHex = fmt.Sprintf("%x", h)
	sig, err := s.Sign(pkgData)
	return hashHex, sig, err
}

// Verify 验签（供客户端参考——客户端使用公钥即可）
func (s *signer) Verify(data []byte, signatureB64 string) bool {
	sig, err := base64.StdEncoding.DecodeString(signatureB64)
	if err != nil {
		return false
	}
	hash := sha256.Sum256(data)
	return rsa.VerifyPKCS1v15(s.publicKey, crypto.SHA256, hash[:], sig) == nil
}

// PublicKeyPEM 返回公钥 PEM，供客户端嵌入
func (s *signer) PublicKeyPEM() []byte {
	return s.publicPEM
}

// PublicKeyJSON 返回公钥 JSON（API 暴露用）
func (s *signer) PublicKeyJSON() ([]byte, error) {
	return json.Marshal(map[string]string{
		"pem":  string(s.publicPEM),
		"alg":  "RS256",
		"bits": fmt.Sprintf("%d", rsaKeyBits),
	})
}
