package main

import (
    "flag"
    "fmt"
    "log"
    "os"

    "github.com/aws/aws-sdk-go/aws"
    "github.com/aws/aws-sdk-go/aws/session"
    "github.com/aws/aws-sdk-go/service/s3"
)

var sizeTable = []string{"Bs", "KBs", "MBs", "GBs", "TBs", "PBs", "EBs"}

func calculateSize(size int64) string {
    count := 0
    floatSize := float64(size)
    for floatSize >= 1024 && count < len(sizeTable)-1 {
        floatSize /= 1024
        count++
    }
    return fmt.Sprintf("%.2f %s", floatSize, sizeTable[count])
}

func getS3Statistics(bucket, prefix string) (map[string]interface{}, error) {
    sess, err := session.NewSession(&aws.Config{
        Region: aws.String("us-east-1"), // Altere para a região do seu bucket
    })
    if err != nil {
        return nil, err
    }

    s3Client := s3.New(sess)

    params := &s3.ListObjectVersionsInput{
        Bucket: aws.String(bucket),
    }

    if prefix != "" {
        params.Prefix = aws.String(prefix)
    }

    deleteMarkerCount := int64(0)
    versionedObjectCount := int64(0)
    versionedObjectSize := int64(0)
    currentObjectCount := int64(0)
    currentObjectSize := int64(0)

    fmt.Println("$ Calculando, por favor aguarde... isso pode levar algum tempo")

    err = s3Client.ListObjectVersionsPages(params,
        func(page *s3.ListObjectVersionsOutput, lastPage bool) bool {
            if len(page.DeleteMarkers) > 0 {
                deleteMarkerCount += int64(len(page.DeleteMarkers))
            }

            if len(page.Versions) > 0 {
                for _, version := range page.Versions {
                    if *version.IsLatest {
                        currentObjectCount++
                        currentObjectSize += *version.Size
                    } else {
                        versionedObjectCount++
                        versionedObjectSize += *version.Size
                    }
                }
            }
            return true
        })

    if err != nil {
        return nil, err
    }

    totalSize := currentObjectSize + versionedObjectSize

    prefixDisplay := prefix
    if prefix == "" {
        prefixDisplay = "(nenhum)"
    }

    return map[string]interface{}{
        "bucket":                 bucket,
        "prefix":                 prefixDisplay,
        "delete_marker_count":    deleteMarkerCount,
        "current_object_count":   currentObjectCount,
        "current_object_size":    calculateSize(currentObjectSize),
        "versioned_object_count": versionedObjectCount,
        "versioned_object_size":  calculateSize(versionedObjectSize),
        "total_size":             calculateSize(totalSize),
    }, nil
}

func main() {
    bucket := flag.String("b", "", "Nome do bucket S3")
    prefix := flag.String("p", "", "Prefixo dos objetos S3 (opcional)")
    flag.Parse()

    if *bucket == "" {
        fmt.Println("Uso: go run script.go -b <nome_do_bucket> [-p <prefixo>]")
        flag.PrintDefaults()
        os.Exit(1)
    }

    stats, err := getS3Statistics(*bucket, *prefix)
    if err != nil {
        log.Fatalf("Erro: %v", err)
    }

    fmt.Println("\n----------")
    fmt.Printf("$ Nome do Bucket: %s\n", stats["bucket"])
    fmt.Printf("$ Prefixo: %s\n", stats["prefix"])
    fmt.Printf("$ Total de Delete Markers: %d\n", stats["delete_marker_count"])
    fmt.Printf("$ Número de Objetos Atuais: %d\n", stats["current_object_count"])
    fmt.Printf("$ Tamanho dos Objetos Atuais: %s\n", stats["current_object_size"])
    fmt.Printf("$ Número de Objetos Não Atuais: %d\n", stats["versioned_object_count"])
    fmt.Printf("$ Tamanho dos Objetos Não Atuais: %s\n", stats["versioned_object_size"])
    fmt.Printf("$ Tamanho Total (Atual + Não Atuais): %s\n", stats["total_size"])
    fmt.Println("----------\n")
    fmt.Println("$ Processo concluído com sucesso")
}
