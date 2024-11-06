package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/s3"
)

type SizeStats struct {
	CurrentSize    int64
	VersionedSize  int64
	CurrentCount   int64
	VersionedCount int64
	DeleteMarkers  int64
	LastModified   time.Time
}

func formatSize(bytes int64) string {
	const (
		B  = 1
		KB = 1024 * B
		MB = 1024 * KB
		GB = 1024 * MB
		TB = 1024 * GB
		PB = 1024 * TB
	)

	switch {
	case bytes >= PB:
		return fmt.Sprintf("%.2f PB", float64(bytes)/float64(PB))
	case bytes >= TB:
		return fmt.Sprintf("%.2f TB", float64(bytes)/float64(TB))
	case bytes >= GB:
		return fmt.Sprintf("%.2f GB", float64(bytes)/float64(GB))
	case bytes >= MB:
		return fmt.Sprintf("%.2f MB", float64(bytes)/float64(MB))
	case bytes >= KB:
		return fmt.Sprintf("%.2f KB", float64(bytes)/float64(KB))
	default:
		return fmt.Sprintf("%d B", bytes)
	}
}

func processBucket(svc *s3.S3, bucket, prefix string, includeVersions bool, detailedOutput bool) (*SizeStats, error) {
	stats := &SizeStats{}
	var mutex sync.Mutex
	var wg sync.WaitGroup

	if includeVersions {
		input := &s3.ListObjectVersionsInput{
			Bucket: aws.String(bucket),
			Prefix: aws.String(prefix),
		}

		err := svc.ListObjectVersionsPages(input, func(page *s3.ListObjectVersionsOutput, lastPage bool) bool {
			wg.Add(1)
			go func() {
				defer wg.Done()
				mutex.Lock()
				for _, v := range page.Versions {
					if *v.IsLatest {
						stats.CurrentSize += *v.Size
						stats.CurrentCount++
						if v.LastModified.After(stats.LastModified) {
							stats.LastModified = *v.LastModified
						}
					} else {
						stats.VersionedSize += *v.Size
						stats.VersionedCount++
					}
				}
				stats.DeleteMarkers += int64(len(page.DeleteMarkers))
				mutex.Unlock()
			}()
			return true
		})
		wg.Wait()
		if err != nil {
			return nil, fmt.Errorf("erro ao listar versões: %v", err)
		}
	} else {
		input := &s3.ListObjectsV2Input{
			Bucket: aws.String(bucket),
			Prefix: aws.String(prefix),
		}

		err := svc.ListObjectsV2Pages(input, func(page *s3.ListObjectsV2Output, lastPage bool) bool {
			wg.Add(1)
			go func() {
				defer wg.Done()
				mutex.Lock()
				for _, obj := range page.Contents {
					stats.CurrentSize += *obj.Size
					stats.CurrentCount++
					if obj.LastModified.After(stats.LastModified) {
						stats.LastModified = *obj.LastModified
					}
				}
				mutex.Unlock()
			}()
			return true
		})
		wg.Wait()
		if err != nil {
			return nil, fmt.Errorf("erro ao listar objetos: %v", err)
		}
	}

	return stats, nil
}

func printProgressBar(progress float64) {
	width := 50
	completed := int(progress * float64(width))
	remaining := width - completed

	fmt.Printf("\r[%s%s] %.1f%%",
		strings.Repeat("=", completed),
		strings.Repeat(" ", remaining),
		progress*100)
}

func main() {
	bucket := flag.String("b", "", "Nome do bucket S3")
	prefix := flag.String("p", "", "Prefixo dos objetos (pasta)")
	includeVersions := flag.Bool("v", false, "Incluir versões antigas")
	detailed := flag.Bool("d", false, "Saída detalhada")
	region := flag.String("r", "us-east-1", "Região AWS")
	flag.Parse()

	if *bucket == "" {
		fmt.Println("Uso: ./s3size -b BUCKET_NAME [-p PREFIX] [-v] [-d] [-r REGION]")
		flag.PrintDefaults()
		os.Exit(1)
	}

	// Configuração da sessão AWS
	sess, err := session.NewSession(&aws.Config{
		Region: aws.String(*region),
	})
	if err != nil {
		log.Fatalf("Erro ao criar sessão AWS: %v", err)
	}

	svc := s3.New(sess)

	fmt.Printf("\nIniciando cálculo para bucket '%s'", *bucket)
	if *prefix != "" {
		fmt.Printf(" com prefixo '%s'", *prefix)
	}
	fmt.Println("\nCalculando...")

	startTime := time.Now()
	stats, err := processBucket(svc, *bucket, *prefix, *includeVersions, *detailed)
	if err != nil {
		log.Fatalf("Erro ao processar bucket: %v", err)
	}
	duration := time.Since(startTime)

	// Limpa a linha do progress bar
	fmt.Print("\r" + strings.Repeat(" ", 80) + "\r")

	fmt.Println("\n=== Relatório de Tamanho do S3 ===")
	fmt.Printf("Bucket: %s\n", *bucket)
	if *prefix != "" {
		fmt.Printf("Prefixo: %s\n", *prefix)
	}
	fmt.Printf("Tempo de execução: %v\n", duration.Round(time.Millisecond))
	fmt.Printf("\nArquivos atuais: %d (Tamanho: %s)\n",
		stats.CurrentCount,
		formatSize(stats.CurrentSize))

	if *includeVersions {
		fmt.Printf("Versões antigas: %d (Tamanho: %s)\n",
			stats.VersionedCount,
			formatSize(stats.VersionedSize))
		fmt.Printf("Marcadores de deleção: %d\n", stats.DeleteMarkers)
		fmt.Printf("Tamanho total (incluindo versões): %s\n",
			formatSize(stats.CurrentSize+stats.VersionedSize))
	}

	if *detailed {
		fmt.Printf("\nÚltima modificação: %v\n", stats.LastModified)
		fmt.Printf("Tamanho médio por arquivo: %s\n",
			formatSize(stats.CurrentSize/stats.CurrentCount))
	}

	fmt.Println("\nCálculo concluído com sucesso!")
}
