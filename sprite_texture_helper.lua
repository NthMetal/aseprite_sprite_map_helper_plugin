function init(plugin)
  local state = {
    textureSprite = nil,
    uvImage = nil,
    preview = nil,
    dlg = nil,
    zoom = 1.0,
    offsetX = 0,
    offsetY = 0,
    dragging = false,
    lastX = 0,
    lastY = 0,
    watcherId = nil,
    useComposite = true
  }

  local function pickUVMap()
    local dlg = Dialog{ title="Select UV Map" }
    dlg:file{
      id="uvmap",
      title="Select UV Map",
      open=true,
      filetypes={ "png", "ase", "aseprite", "gif", "jpg" }
    }
    dlg:button{ id="ok", text="OK" }
    dlg:button{ id="cancel", text="Cancel" }
    dlg:show()
    if not dlg.data.ok then return false end
    local path = dlg.data.uvmap
    if not path or path == "" then return false end
    local uvSprite = app.open(path)
    if not uvSprite then
      app.alert("Failed to open UV map")
      return false
    end
    local src = Image(uvSprite.cels[1].image)
    local tmp = Image(src.width, src.height, ColorMode.RGB)
    tmp:drawImage(src, 0, 0)
    uvSprite:close()
    state.uvImage = tmp
    return true
  end

  local function makePreview()
    if not (state.textureSprite and state.uvImage) then return end
    local baseImg = nil
    if state.useComposite then
      baseImg = Image(state.textureSprite.width,
                          state.textureSprite.height,
                          ColorMode.RGB)
      baseImg:drawSprite(state.textureSprite, app.activeFrame)
    else
      local baseCel = app.cel;if not baseCel then return end
      baseImg = Image(baseCel.image, ColorMode.RGB)
    end

    local comp = Image(state.uvImage.width, state.uvImage.height, ColorMode.RGB)
    for y=0, comp.height-1 do
      for x=0, comp.width-1 do
        local px = state.uvImage:getPixel(x, y)
        local u = app.pixelColor.rgbaR(px)
        local v = math.max(app.pixelColor.rgbaG(px), app.pixelColor.rgbaB(px))
        if u < baseImg.width and v < baseImg.height then
          local c = baseImg:getPixel(u, v)
          comp:putPixel(x, y, c)
        end
      end
    end
    state.preview = comp
  end

  local function drawCheckerboard(ctx, width, height, offsetX, offsetY, zoom)
    local tileSize = 8 * zoom
    local lightGray = Color{ r=192, g=192, b=192 }
    local darkGray  = Color{ r=128, g=128, b=128 }
    local tilesX = math.ceil(width * zoom / tileSize)
    local tilesY = math.ceil(height * zoom / tileSize)
    for ty = 0, tilesY - 1 do
      for tx = 0, tilesX - 1 do
        local x = math.floor(offsetX + tx * tileSize)
        local y = math.floor(offsetY + ty * tileSize)
        local isLight = ((tx + ty) % 2 == 0)
        ctx.color = isLight and lightGray or darkGray
        ctx:fillRect(x, y, math.ceil(tileSize)+1, math.ceil(tileSize)+1)
      end
    end
  end

  local function showPreviewDialog()
    if not state.preview then return end
    if state.dlg then state.dlg:repaint(); return end
    local dlg = Dialog{ title="UV Preview" }
    dlg:canvas{
      id="canvas",
      width=state.preview.width,
      height=state.preview.height,
      onpaint=function(ev)
        local img = state.preview
        local z = state.zoom
        local ctx = ev.context
        drawCheckerboard(ctx, img.width, img.height, state.offsetX, state.offsetY, z)
        ctx:drawImage(img, 0, 0, img.width, img.height,
                      state.offsetX, state.offsetY,
                      img.width*z, img.height*z)
        ctx:save()
        ctx.color = Color{ r=0, g=0, b=0 }
        ctx.strokeWidth = 1
        ctx:strokeRect(state.offsetX + 0.5, state.offsetY + 0.5,
                       img.width * z, img.height * z)
        ctx:restore()
      end,
      onwheel=function(ev)
        local oldZ = state.zoom
        local factor = ev.deltaY < 0 and 1.25 or 0.8
        local newZ = math.max(0.05, math.min(oldZ * factor, 32))
        local mx, my = ev.x, ev.y
        state.zoom = newZ
        state.offsetX = mx - (mx - state.offsetX) * (newZ / oldZ)
        state.offsetY = my - (my - state.offsetY) * (newZ / oldZ)
        dlg:repaint()
      end,
      onmousedown=function(ev)
        if ev.button == MouseButton.MIDDLE then
          state.dragging = true
          state.lastX, state.lastY = ev.x, ev.y
        end
      end,
      onmouseup=function(ev)
        if ev.button == MouseButton.MIDDLE then
          state.dragging = false
        end
      end,
      onmousemove=function(ev)
        if state.dragging then
          local dx = ev.x - state.lastX
          local dy = ev.y - state.lastY
          state.offsetX = state.offsetX + dx
          state.offsetY = state.offsetY + dy
          state.lastX, state.lastY = ev.x, ev.y
          dlg:repaint()
        end
      end
    }
    dlg:check{
      id="composite",
      label = "",
      text = "Composite all visible layers",
      selected=state.useComposite,
      onclick=function()
        state.useComposite = dlg.data.composite  -- Fixed: was dlg.data.compositeLayers
        makePreview()
        dlg:repaint()
      end
    }
    dlg:button{
      text="Reset",
      onclick=function()
        state.zoom = 1.0
        state.offsetX = 0
        state.offsetY = 0
        dlg:repaint()
      end
    }
    dlg:button{
      text="Close",
      onclick=function()
        dlg:close()
        state.dlg = nil
      end
    }
    dlg:show{ wait=false }
    state.dlg = dlg
  end

  local function installWatcher()
    if not state.textureSprite then return end
    if state.watcherId then
      state.textureSprite.events:off(state.watcherId)
      state.watcherId = nil
    end
    state.watcherId = state.textureSprite.events:on("change", function()
      makePreview()
      if state.dlg then state.dlg:repaint() end
    end)
  end

  app.events:on("sitechange", function()
    if state.textureSprite and state.uvImage then
      makePreview()
      if state.dlg then state.dlg:repaint() end
    end
  end)

  function exit(plugin)
    if state.textureSprite and state.watcherId then
      state.textureSprite.events:off(state.watcherId)
      state.watcherId = nil
    end
  end

  plugin:newCommand{
    id="sprite_texture_helper_id",
    title="Sprite Texture Helper",
    group="edit_insert",
    onclick=function()
      local spr = app.activeSprite
      if not spr then
        app.alert("Please open a texture image first.")
        return
      end
      state.textureSprite = spr
      if pickUVMap() then
        makePreview()
        showPreviewDialog()
        installWatcher()
      end
    end
  }
end