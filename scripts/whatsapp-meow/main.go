package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/mdp/qrterminal"
	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/store/sqlstore"
	"go.mau.fi/whatsmeow/types/events"
	waLog "go.mau.fi/whatsmeow/util/log"
)

type MessageStore struct {
	JID       string    `json:"jid"`
	Sender    string    `json:"sender"`
	Name      string    `json:"name"`
	Message   string    `json:"message"`
	Timestamp time.Time `json:"timestamp"`
	IsFromMe  bool      `json:"is_from_me"`
}

var client *whatsmeow.Client
var messageStore []MessageStore
const maxStoreSize = 1000

func main() {
	log.Println("[WhatsMeow] Iniciando...")
	
	sessionName := os.Getenv("WHATSMEOW_SESSION")
	if sessionName == "" {
		sessionName = "default"
	}
	port := os.Getenv("WHATSMEOW_PORT")
	if port == "" {
		port = "3002"
	}

	os.MkdirAll(fmt.Sprintf("/opt/data/whatsapp-meow/%s", sessionName), 0755)

	dbPath := fmt.Sprintf("/opt/data/whatsapp-meow/%s/store.db", sessionName)
	
	var err error
	container, err := sqlstore.New("sqlite3", fmt.Sprintf("file:%s?_foreign_keys=on", dbPath), nil)
	if err != nil {
		log.Fatal(err)
	}

	deviceStore, err := container.GetFirstDevice()
	if err != nil {
		log.Fatal(err)
	}
	if deviceStore == nil {
		deviceStore = container.NewDevice()
	}

	client = whatsmeow.NewClient(deviceStore, nil)
	client.AddEventHandler(eventHandler)

	if client.Store.ID == nil {
		log.Println("[WhatsMeow] No existe sesion, generando QR...")
		qrChan, _ := client.GetQRChannel(context.Background())
		err = client.Connect()
		if err != nil {
			log.Fatal(err)
		}
		for evt := range qrChan {
			if evt.Event == "code" {
				qrterminal.GenerateHalfBlock(evt.Code, qrterminal.L, os.Stdout)
				log.Println("Escanea el QR para", sessionName)
			} else {
				log.Println("Evento:", evt.Event)
			}
		}
	} else {
		err = client.Connect()
		if err != nil {
			log.Fatal(err)
		}
		log.Println("[WhatsMeow] Conectado!")
	}

	http.HandleFunc("/health", healthHandler)
	http.HandleFunc("/messages", messagesHandler)
	http.HandleFunc("/status", statusHandler)

	log.Println("[WhatsMeow] API en puerto", port)
	go http.ListenAndServe(":"+port, nil)

	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt, syscall.SIGTERM)
	<-c
	log.Println("[WhatsMeow] Desconectando...")
	client.Disconnect()
}

func eventHandler(evt interface{}) {
	switch v := evt.(type) {
	case *events.Message:
		storeMessage(v)
	case *events.Connected:
		log.Println("[WhatsMeow] Conectado a WhatsApp!")
	case *events.Disconnected:
		log.Println("[WhatsMeow] Desconectado")
	}
}

func storeMessage(msg *events.Message) {
	var text string
	if msg.Message.GetConversation() != "" {
		text = msg.Message.GetConversation()
	} else if msg.Message.GetExtendedTextMessage() != nil {
		text = msg.Message.GetExtendedTextMessage().GetText()
	}
	if text == "" {
		return
	}

	store := MessageStore{
		JID:       msg.Info.Chat.String(),
		Sender:    msg.Info.Sender.String(),
		Name:      msg.Info.PushName,
		Message:   text,
		Timestamp: msg.Info.Timestamp,
		IsFromMe:  msg.Info.IsFromMe,
	}

	messageStore = append(messageStore, store)
	if len(messageStore) > maxStoreSize {
		messageStore = messageStore[len(messageStore)-maxStoreSize:]
	}
	
	log.Printf("[MENSAJE] %s: %s", store.Name, store.Message[:min(50,len(store.Message))])
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	json.NewEncoder(w).Encode(map[string]interface{}{
		"connected": client.IsConnected(),
		"logged_in": client.Store.ID != nil,
	})
}

func messagesHandler(w http.ResponseWriter, r *http.Request) {
	json.NewEncoder(w).Encode(messageStore)
}

func statusHandler(w http.ResponseWriter, r *http.Request) {
	json.NewEncoder(w).Encode(map[string]interface{}{
		"connected":      client.IsConnected(),
		"logged_in":      client.Store.ID != nil,
		"messages_count": len(messageStore),
	})
}
