// Copyright (c) Chemsource Studio. All rights reserved.
// Backend Version 2.2.0.260614-r1

package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

const maxSpaceImages = 9

func apiSpaceSend(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	myUID, ok := requireLogin(c)
	if !ok {
		return
	}
	content := strings.TrimSpace(c.InputString("content"))
	imageURLs := uploadSpaceImages(c)
	if content == "" && len(imageURLs) == 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "请提供文字内容或图片"})
		return
	}
	if content == "" {
		content = "分享图片"
	}
	var imgConts any = nil
	if len(imageURLs) > 0 {
		data, _ := json.Marshal(imageURLs)
		imgConts = string(data)
	}
	contID, err := c.app.insertRow("space_shc", map[string]any{
		"sender_uid": myUID,
		"content":    content,
		"img_conts":  nullableString(toString(imgConts)),
		"is_reply":   0,
		"likes_uid":  "",
		"likes_num":  0,
		"created_at": localDateTime(time.Now().Unix()),
	})
	if err != nil {
		log.Printf("[space] insertRow send error: %v (uid=%d, img_conts=%v)", err, myUID, imgConts)
		c.JSON(http.StatusInternalServerError, map[string]any{"success": false, "message": "发布失败"})
		return
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "发布成功", "cont_id": contID})
}

func apiSpaceDelete(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	myUID, ok := requireLogin(c)
	if !ok {
		return
	}
	contID := c.InputInt("cont_id")
	if contID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "无效的动态ID"})
		return
	}
	row, err := c.app.fetchOne("SELECT sender_uid FROM space_shc WHERE cont_id = ?", contID)
	if err != nil || row == nil {
		c.JSON(http.StatusNotFound, map[string]any{"success": false, "message": "动态不存在"})
		return
	}
	if intval(row, "sender_uid") != myUID {
		c.JSON(http.StatusForbidden, map[string]any{"success": false, "message": "只能删除自己的动态"})
		return
	}
	_, err = c.app.exec("DELETE FROM space_shc WHERE cont_id = ?", contID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, map[string]any{"success": false, "message": "删除失败"})
		return
	}
	_, _ = c.app.exec("DELETE FROM space_shc WHERE is_reply = 1 AND reply_id = ?", contID)
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "删除成功"})
}

func apiSpaceToggleLike(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	myUID, ok := requireLogin(c)
	if !ok {
		return
	}
	contID := c.InputInt("cont_id")
	if contID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "无效的动态ID"})
		return
	}
	row, err := c.app.fetchOne("SELECT likes_uid, likes_num FROM space_shc WHERE cont_id = ?", contID)
	if err != nil || row == nil {
		c.JSON(http.StatusNotFound, map[string]any{"success": false, "message": "动态不存在"})
		return
	}
	likesUID := str(row, "likes_uid")
	likesNum := intval(row, "likes_num")
	uidStr := fmt.Sprintf("%d", myUID)
	uidMap := map[string]bool{}
	if likesUID != "" {
		for _, id := range strings.Split(likesUID, ",") {
			id = strings.TrimSpace(id)
			if id != "" {
				uidMap[id] = true
			}
		}
	}
	liked := uidMap[uidStr]
	if liked {
		delete(uidMap, uidStr)
		if likesNum > 0 {
			likesNum--
		}
	} else {
		uidMap[uidStr] = true
		likesNum++
	}
	var list []string
	for id := range uidMap {
		list = append(list, id)
	}
	sort.Strings(list)
	newLikesUID := strings.Join(list, ",")
	_, err = c.app.updateRow("space_shc", map[string]any{
		"likes_uid": newLikesUID,
		"likes_num": likesNum,
	}, "cont_id = ?", contID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, map[string]any{"success": false, "message": "操作失败"})
		return
	}
	action := "已点赞"
	if liked {
		action = "已取消点赞"
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": action, "is_liked": !liked, "likes_num": likesNum})
}

func apiSpaceReply(c *Ctx) {
	if !c.RequireMethod(http.MethodPost) {
		return
	}
	myUID, ok := requireLogin(c)
	if !ok {
		return
	}
	replyID := c.InputInt("reply_id")
	if replyID <= 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "缺少 reply_id 参数"})
		return
	}
	target, err := c.app.fetchOne("SELECT cont_id FROM space_shc WHERE cont_id = ?", replyID)
	if err != nil || target == nil {
		c.JSON(http.StatusNotFound, map[string]any{"success": false, "message": "回复的目标动态不存在"})
		return
	}
	content := strings.TrimSpace(c.InputString("content"))
	imageURLs := uploadSpaceImages(c)
	if content == "" && len(imageURLs) == 0 {
		c.JSON(http.StatusOK, map[string]any{"success": false, "message": "请提供文字内容或图片"})
		return
	}
	if content == "" {
		content = "分享图片"
	}
	var imgConts any = nil
	if len(imageURLs) > 0 {
		data, _ := json.Marshal(imageURLs)
		imgConts = string(data)
	}
	contID, err := c.app.insertRow("space_shc", map[string]any{
		"sender_uid": myUID,
		"content":    content,
		"img_conts":  nullableString(toString(imgConts)),
		"is_reply":   1,
		"reply_id":   replyID,
		"likes_uid":  "",
		"likes_num":  0,
		"created_at": localDateTime(time.Now().Unix()),
	})
	if err != nil {
		log.Printf("[space] insertRow reply error: %v (uid=%d, reply_id=%d, img_conts=%v)", err, myUID, replyID, imgConts)
		c.JSON(http.StatusInternalServerError, map[string]any{"success": false, "message": "回复失败"})
		return
	}
	c.JSON(http.StatusOK, map[string]any{"success": true, "message": "回复成功", "cont_id": contID, "reply_id": replyID})
}

func uploadSpaceImages(c *Ctx) []string {
	var urls []string
	maxTotal := c.app.config.MaxImageBytes*int64(maxSpaceImages) + 10*1024*1024
	if err := c.r.ParseMultipartForm(maxTotal); err != nil && c.r.MultipartForm == nil {
		log.Printf("[space] ParseMultipartForm error: %v", err)
		return urls
	}
	if c.r.MultipartForm == nil || c.r.MultipartForm.File == nil {
		log.Printf("[space] MultipartForm or File is nil")
		return urls
	}
	headers := c.r.MultipartForm.File["images"]
	if len(headers) == 0 {
		return urls
	}
	if len(headers) > maxSpaceImages {
		headers = headers[:maxSpaceImages]
	}
	absoluteDir := filepath.Join(c.app.config.UploadDir, "space_img")
	publicPrefix := "upload/space_img"
	if err := os.MkdirAll(absoluteDir, 0775); err != nil {
		log.Printf("[space] MkdirAll error: %v (dir=%s)", err, absoluteDir)
		return urls
	}
	for i, header := range headers {
		if header.Size > c.app.config.MaxImageBytes {
			log.Printf("[space] image %d too large: %d > %d", i, header.Size, c.app.config.MaxImageBytes)
			continue
		}
		file, err := header.Open()
		if err != nil {
			log.Printf("[space] open image %d error: %v", i, err)
			continue
		}
		mime, first, err := detectUploadMime(file, header)
		if err != nil {
			log.Printf("[space] detect mime image %d error: %v", i, err)
			file.Close()
			continue
		}
		if len(imageMimes) > 0 && mime != "" && !mimeAllowed(mime, imageMimes, header.Filename) {
			log.Printf("[space] mime not allowed image %d: %s (file=%s)", i, mime, header.Filename)
			file.Close()
			continue
		}
		ext := uploadExt(mime, header.Filename, imageMimes)
		name := fmt.Sprintf("space_%d_%s_%d_%d.%s", c.session.UID, randomHex(4), time.Now().Unix(), i, ext)
		dest := filepath.Join(absoluteDir, name)
		out, err := os.OpenFile(dest, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0664)
		if err != nil {
			log.Printf("[space] create file image %d error: %v (dest=%s)", i, err, dest)
			file.Close()
			continue
		}
		if len(first) > 0 {
			if _, err := out.Write(first); err != nil {
				log.Printf("[space] write first bytes image %d error: %v", i, err)
			}
		}
		if _, err := io.Copy(out, file); err != nil {
			log.Printf("[space] copy image %d error: %v", i, err)
		}
		file.Close()
		out.Close()
		urls = append(urls, strings.TrimRight(publicPrefix, "/")+"/"+name)
	}
	log.Printf("[space] uploaded %d images", len(urls))
	return urls
}

func apiSpaceGetList(c *Ctx) {
	myUID, ok := requireLogin(c)
	if !ok {
		return
	}
	page := c.InputInt("page", 1)
	if page < 1 {
		page = 1
	}
	pageSize := c.InputInt("page_size", 20)
	if pageSize < 1 {
		pageSize = 20
	}
	if pageSize > 50 {
		pageSize = 50
	}
	offset := (page - 1) * pageSize

	friendRows, err := c.app.fetchAll(`SELECT CASE WHEN uid1 = ? THEN uid2 ELSE uid1 END AS friend_id FROM friend_relation WHERE status = 1 AND (uid1 = ? OR uid2 = ?)`, myUID, myUID, myUID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, map[string]any{"success": false, "message": "查询失败"})
		return
	}
	uidSet := map[int64]bool{myUID: true}
	for _, row := range friendRows {
		uidSet[intval(row, "friend_id")] = true
	}
	uids := make([]any, 0, len(uidSet))
	for uid := range uidSet {
		uids = append(uids, uid)
	}
	placeholders := make([]string, len(uids))
	for i := range placeholders {
		placeholders[i] = "?"
	}
	inClause := strings.Join(placeholders, ",")

	totalRow, _ := c.app.fetchOne("SELECT COUNT(*) AS total FROM space_shc WHERE is_reply = 0 AND sender_uid IN ("+inClause+")", uids...)
	total := intval(totalRow, "total")

	args := append(uids, pageSize, offset)
	rows, err := c.app.fetchAll("SELECT s.*, u.nickname, u.avatar FROM space_shc s JOIN chat_user u ON s.sender_uid = u.id WHERE s.is_reply = 0 AND s.sender_uid IN ("+inClause+") ORDER BY s.cont_id DESC LIMIT ? OFFSET ?", args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, map[string]any{"success": false, "message": "查询失败"})
		return
	}

	list := make([]map[string]any, 0, len(rows))
	contIDs := make([]any, 0, len(rows))
	contIDToIntIdx := map[int64]int{}
	for i, row := range rows {
		contIDs = append(contIDs, intval(row, "cont_id"))
		contIDToIntIdx[intval(row, "cont_id")] = i
		list = append(list, nil)
	}
	var replyGroups map[int64][]map[string]any
	if len(contIDs) > 0 {
		replyPh := make([]string, len(contIDs))
		for i := range replyPh {
			replyPh[i] = "?"
		}
		replyRows, _ := c.app.fetchAll(
			"SELECT s.*, u.nickname, u.avatar FROM space_shc s JOIN chat_user u ON s.sender_uid = u.id WHERE s.is_reply = 1 AND s.reply_id IN ("+strings.Join(replyPh, ",")+") ORDER BY s.cont_id ASC",
			contIDs...,
		)
		replyGroups = make(map[int64][]map[string]any, len(contIDs))
		for _, r := range replyRows {
			rid := intval(r, "reply_id")
			replyGroups[rid] = append(replyGroups[rid], buildSpaceItem(c, r, myUID))
		}
	}
	for i, row := range rows {
		item := buildSpaceItem(c, row, myUID)
		cid := intval(row, "cont_id")
		if replies, ok := replyGroups[cid]; ok {
			item["replies"] = replies
		} else {
			item["replies"] = []map[string]any{}
		}
		list[i] = item
	}

	c.JSON(http.StatusOK, map[string]any{
		"success":   true,
		"list":      list,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

func buildSpaceItem(c *Ctx, row Row, myUID int64) map[string]any {
	contID := intval(row, "cont_id")
	senderUID := intval(row, "sender_uid")
	likesUID := str(row, "likes_uid")
	likesNum := intval(row, "likes_num")
	uidStr := strconv.FormatInt(myUID, 10)
	isLiked := false
	if likesUID != "" {
		for _, id := range strings.Split(likesUID, ",") {
			if strings.TrimSpace(id) == uidStr {
				isLiked = true
				break
			}
		}
	}
	var imgList []string
	imgConts := str(row, "img_conts")
	if imgConts != "" {
		_ = json.Unmarshal([]byte(imgConts), &imgList)
	}
	if imgList == nil {
		imgList = []string{}
	}
	return map[string]any{
		"cont_id":    contID,
		"sender_uid": senderUID,
		"nickname":   str(row, "nickname"),
		"avatar":     avatarOrDefault(c.app, str(row, "avatar")),
		"content":    str(row, "content"),
		"img_conts":  imgList,
		"is_reply":   intval(row, "is_reply"),
		"reply_id":   row["reply_id"],
		"likes_num":  likesNum,
		"is_liked":   isLiked,
		"created_at": str(row, "created_at"),
	}
}
