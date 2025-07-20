function init(plugin)
  local state = {
    -- input images
    baseSprite       = nil,
    overlayImage     = nil,

    -- preview 1
    preview1 = nil, dlg1 = nil,
    zoom1 = 1.0, offX1 = 0, offY1 = 0,
    drag1 = false, lx1 = 0, ly1 = 0,

    -- preview 2
    preview2 = nil, dlg2 = nil,
    zoom2 = 1.0, offX2 = 0, offY2 = 0,
    drag2 = false, moved2 = false,
    lx2 = 0, ly2 = 0,
    hoverX2 = nil, hoverY2 = nil,
    selX2   = nil, selY2   = nil,

    watcherId = nil,
    sampleComposite = false,
    conns = {}
  }

  function addRGBA(p1, p2)
    local r = math.min(app.pixelColor.rgbaR(p1) + app.pixelColor.rgbaR(p2), 255)
    local g = math.min(app.pixelColor.rgbaG(p1) + app.pixelColor.rgbaG(p2), 255)
    local b = math.min(app.pixelColor.rgbaB(p1) + app.pixelColor.rgbaB(p2), 255)
    local a = math.min(app.pixelColor.rgbaA(p1) + app.pixelColor.rgbaA(p2), 255)
    return app.pixelColor.rgba(r, g, b, a)
  end

  function pickOverlay()
    local spr = app.activeSprite
    if not spr then
      app.alert("Please open a sprite first.")
      return false
    end

    local dlg = Dialog{ title="Select Texture Image" }
    dlg:file{
      id        = "overlay",
      title     = "Select Texture",
      open      = true,
      filetypes = { "png", "ase", "aseprite", "gif", "jpg" }
    }
    dlg:button{ id="ok",     text="OK" }
    dlg:button{ id="cancel", text="Cancel" }

    dlg:show()
    if not dlg.data.ok then return false end

    local path = dlg.data.overlay
    if not path or path == "" then return false end

    local ovSpr = app.open(path)
    if not ovSpr then
      app.alert("Failed to open image:\n" .. path)
      return false
    end

    local src = Image(ovSpr.cels[1].image)
    local tmp = Image(src.width, src.height, ColorMode.RGB)
    tmp:drawImage(src, 0, 0)

    state.baseSprite   = spr
    state.overlayImage = tmp
    ovSpr:close()
    return true
  end

  function makePreview1()
    if not (state.baseSprite and state.overlayImage) then return end

    local baseImg = nil
    if state.sampleComposite then
      baseImg = Image(state.baseSprite.width,
                          state.baseSprite.height,
                          ColorMode.RGB)
      baseImg:drawSprite(state.baseSprite, app.activeFrame)
    else
      local baseCel = app.cel; if not baseCel then return end
      baseImg = Image(baseCel.image, ColorMode.RGB)
    end



    local w,h     = baseImg.width, baseImg.height
    local ovImg   = state.overlayImage
    local comp    = Image(w, h, ColorMode.RGB)

    for y=0, h-1 do
      for x=0, w-1 do
        local pBase = baseImg:getPixel(x,y)
        local cx    = app.pixelColor.rgbaR(pBase)
        local cy    = math.max(app.pixelColor.rgbaG(pBase),
                              app.pixelColor.rgbaB(pBase))
        local pOut  = 0
        if cx < ovImg.width and cy < ovImg.height then
          pOut = ovImg:getPixel(cx, cy)
        end
        comp:putPixel(x,y,pOut)
      end
    end
    state.preview1 = comp
    -- if state.dlg1 then
    --   state.dlg1:modify{
    --     id     = "canvas1",
    --     width  = comp.width,
    --     height = comp.height
    --   }
    --   local bounds = state.dlg1.bounds
    --   state.dlg1.bounds = Rectangle{
    --     x = bounds.x,
    --     y = bounds.y,
    --     width  = comp.width,
    --     height = comp.height
    --   }
    --   state.dlg1:repaint()
    -- end
  end

  function makePreview2()
    if not state.overlayImage then return end
    state.preview2 = state.overlayImage
  end

  function addCanvas(dlg, id, previewKey,
                          zoomKey, offXKey, offYKey,
                          dragKey, lxKey, lyKey)

    dlg:canvas{
      id     = id,
      width  = state[previewKey].width,
      height = state[previewKey].height,

      onpaint = function(ev)
        local img = state[previewKey]; if not img then return end
        local z   = state[zoomKey]
        local ctx = ev.context
        -- checkerd background
        local ctx = ev.context
        local z = state.zoom1
        local tileSize = 8 * z

        local lightGray = Color{ r=192, g=192, b=192 }
        local darkGray  = Color{ r=128, g=128, b=128 }

        local size = math.max(img.width, img.height) * z

        local imgCenterX = state.offX1 + (img.width * z) / 2
        local imgCenterY = state.offY1 + (img.height * z) / 2

        -- Top-left corner of the square area
        local boxX = imgCenterX - size / 2
        local boxY = imgCenterY - size / 2

        -- How many full tiles fit in the box
        local tilesCount = math.ceil(size / tileSize)

        -- Calculate total tiles width and height in pixels
        local totalTilesWidth  = tilesCount * tileSize
        local totalTilesHeight = tilesCount * tileSize

        -- Offset to center the checkerboard pattern inside the box:
        -- shift pattern origin by half the difference between total tile size and box size
        local offsetX = boxX - (totalTilesWidth - size) / 2
        local offsetY = boxY - (totalTilesHeight - size) / 2

        for ty = 0, tilesCount - 1 do
          for tx = 0, tilesCount - 1 do
            local x = math.floor(offsetX + tx * tileSize)
            local y = math.floor(offsetY + ty * tileSize)
            local w2 = math.ceil(tileSize) + 1
            local h2 = math.ceil(tileSize) + 1

            local isLight = ((tx + ty) % 2 == 0)
            ctx.color = isLight and lightGray or darkGray
            ctx:fillRect(x, y, w2, h2)
          end
        end
        -- image
        ctx:drawImage(img,
                      0, 0, img.width, img.height,
                      state[offXKey], state[offYKey],
                      img.width*z, img.height*z)

        -- black border
        ctx:save()
        ctx.color = Color{ r=0, g=0, b=0 }
        ctx.strokeWidth = 1
        ctx:strokeRect(state[offXKey] + 0.5,
                      state[offYKey] + 0.5,
                      img.width * z,
                      img.height * z)
        ctx:restore()
      end,

      onwheel = function(ev)
        local dx = ev.deltaX or 0
        local dy = ev.deltaY or 0
        if math.abs(dy) >= math.abs(dx) then
          local old  = state[zoomKey]
          local fac  = (dy < 0) and 1.25 or 0.8          -- in  / out
          local nz   = math.max(0.05, math.min(old*fac, 32))
          state[zoomKey] = nz

          -- zoom around the mouse cursor
          local mx, my = ev.x, ev.y
          state[offXKey] = mx - (mx - state[offXKey]) * (nz / old)
          state[offYKey] = my - (my - state[offYKey]) * (nz / old)
        else
          local panStep = 20           -- tune this to taste
          state[offXKey] = state[offXKey] - dx * panStep
        end

        dlg:repaint()
      end,

      onmousedown = function(ev)
        if ev.button==MouseButton.MIDDLE then
          state[dragKey] = true
          state[lxKey], state[lyKey] = ev.x, ev.y
        end
      end,
      onmouseup = function(ev) if ev.button==MouseButton.MIDDLE then state[dragKey]=false end end,
      onmousemove = function(ev)
        if state[dragKey] then
          local dx,dy = ev.x-state[lxKey], ev.y-state[lyKey]
          state[offXKey] = state[offXKey] + dx
          state[offYKey] = state[offYKey] + dy
          state[lxKey], state[lyKey] = ev.x, ev.y
          dlg:repaint()
        end
      end,
    }
  end

  function showDialog1()
    if not state.preview1 then return end
    if state.dlg1 then state.dlg1:repaint(); return end
    local dlg = Dialog{ title="Preview" }

    addCanvas(dlg,"canvas1","preview1","zoom1","offX1","offY1",
                    "drag1","lx1","ly1")


    dlg:check{
      id = "compositeLayers",
      label = "",
      text = "Composite all visible layers",
      selected = state.sampleComposite,
      onclick = function()
        state.sampleComposite = dlg.data.compositeLayers
        makePreview1()
        dlg:repaint()
      end
    }

    dlg:button{
      id = "reset",
      text = "Reset",
      onclick = function()
        state.zoom1 = 1.0
        state.offX1 = 0
        state.offY1 = 0
        dlg:repaint()
      end
    }

    dlg:button{
      text = "Close",
      onclick = function()
        dlg:close()
        state.dlg1 = nil
        if not state.dlg2 then
          cleanupWatchers()
        end
      end
    }

    dlg:show{ wait=false }
    state.dlg1 = dlg
  end

  function pix2screen(px, off, z)
    return math.floor(off + px * z + 0.5)
  end

  function pixsize(z)
    return math.max(1, math.floor(z + 0.5))
  end

  function showDialog2()
    if not state.preview2 then return end
    if state.dlg2 then state.dlg2:repaint(); return end

    local dlg = Dialog{ title="Textrue Sampler" }

    dlg:canvas{
      id     = "canvas2",
      width  = state.preview2.width,
      height = state.preview2.height,

      onpaint = function(ev)
        local img = state.preview2; if not img then return end
        local z   = state.zoom2
        local ctx = ev.context

        -- checkered
        local ctx = ev.context
        local z = state.zoom2
        local tileSize = 8 * z

        local lightGray = Color{ r=192, g=192, b=192 }
        local darkGray  = Color{ r=128, g=128, b=128 }

        local size = math.max(img.width, img.height) * z

        local imgCenterX = state.offX2 + (img.width * z) / 2
        local imgCenterY = state.offY2 + (img.height * z) / 2

        -- Top-left corner of the square area
        local boxX = imgCenterX - size / 2
        local boxY = imgCenterY - size / 2

        -- How many full tiles fit in the box
        local tilesCount = math.ceil(size / tileSize)

        -- Calculate total tiles width and height in pixels
        local totalTilesWidth  = tilesCount * tileSize
        local totalTilesHeight = tilesCount * tileSize

        -- Offset to center the checkerboard pattern inside the box:
        -- shift pattern origin by half the difference between total tile size and box size
        local offsetX = boxX - (totalTilesWidth - size) / 2
        local offsetY = boxY - (totalTilesHeight - size) / 2

        for ty = 0, tilesCount - 1 do
          for tx = 0, tilesCount - 1 do
            local x = math.floor(offsetX + tx * tileSize)
            local y = math.floor(offsetY + ty * tileSize)
            local w2 = math.ceil(tileSize) + 1
            local h2 = math.ceil(tileSize) + 1

            local isLight = ((tx + ty) % 2 == 0)
            ctx.color = isLight and lightGray or darkGray
            ctx:fillRect(x, y, w2, h2)
          end
        end
        -- image
        ctx:drawImage(img, 0,0, img.width, img.height,
                state.offX2, state.offY2,
                img.width*z, img.height*z)

        -- black border
        ctx:save()
        ctx.color = Color{ r=0, g=0, b=0 }
        ctx.strokeWidth = 1
        ctx:strokeRect(state.offX2 + 0.5,
                      state.offY2 + 0.5,
                      img.width * z,
                      img.height * z)
        ctx:restore()

        if state.hoverX2 and state.hoverY2 then
          local x = pix2screen(state.hoverX2, state.offX2, state.zoom2)
          local y = pix2screen(state.hoverY2, state.offY2, state.zoom2)
          local w = pixsize(state.zoom2)

          ctx:save()
          ctx.color       = Color{ r=255, g=0, b=0 }
          ctx.strokeWidth = 1
          ctx:strokeRect(x+0.5, y+0.5, w, w)
          ctx:restore()
        end

        if state.selX2 and state.selY2 then
          local x  = pix2screen(state.selX2, state.offX2, state.zoom2)
          local y  = pix2screen(state.selY2, state.offY2, state.zoom2)
          local w  = pixsize(state.zoom2)

          local cw, ch = ctx.width, ctx.height
          local midX   = x + w/2
          local midY   = y + w/2

          ctx:save()
          ctx.color       = Color{ r=0, g=0, b=255 }
          ctx.strokeWidth = 2
          ctx:strokeRect(x+0.5, y+0.5, w, w)

          ctx.strokeWidth = 1
          ctx:beginPath()
            -- up
            ctx:moveTo(midX+0.5, 0)
            ctx:lineTo(midX+0.5, y)
            -- down
            ctx:moveTo(midX+0.5, y + w)
            ctx:lineTo(midX+0.5, ch)
            -- left
            ctx:moveTo(0,        midY+0.5)
            ctx:lineTo(x,        midY+0.5)
            -- right
            ctx:moveTo(x + w,    midY+0.5)
            ctx:lineTo(cw,       midY+0.5)
          ctx:stroke()
          ctx:restore()
        end
      end,

      onwheel = function(ev)
        local dx = ev.deltaX or 0
        local dy = ev.deltaY or 0
        if math.abs(dy) >= math.abs(dx) then
          local old  = state.zoom2
          local fac  = (dy < 0) and 1.25 or 0.8          -- in  / out
          local nz   = math.max(0.05, math.min(old*fac, 32))
          state.zoom2 = nz

          -- zoom around the mouse cursor
          local mx, my = ev.x, ev.y
          state.offX2 = mx - (mx - state.offX2) * (nz / old)
          state.offY2 = my - (my - state.offY2) * (nz / old)
        else
          local panStep = 20           -- tune this to taste
          state.offX2 = state.offX2 - dx * panStep
        end

        dlg:repaint()
      end,

      onmousedown = function(ev)
        if ev.button == MouseButton.MIDDLE then
          state.drag2  = true
          state.moved2 = false
          state.lx2, state.ly2 = ev.x, ev.y
        elseif ev.button == MouseButton.LEFT then
          state.moved2 = false
        end
      end,

      onmousemove = function(ev)
        -- update hover pixel every move
        local px = math.floor((ev.x - state.offX2) / state.zoom2)
        local py = math.floor((ev.y - state.offY2) / state.zoom2)
        if px>=0 and px<state.preview2.width and py>=0 and py<state.preview2.height then
          state.hoverX2, state.hoverY2 = px, py
        else
          state.hoverX2, state.hoverY2 = nil, nil
        end

        -- if dragging, pan
        if state.drag2 then
          local dx,dy = ev.x - state.lx2, ev.y - state.ly2
          if dx~=0 or dy~=0 then state.moved2 = true end
          state.offX2, state.offY2 = state.offX2+dx, state.offY2+dy
          state.lx2,  state.ly2    = ev.x, ev.y
        end
        dlg:repaint()
      end,

      onmouseup = function(ev)
        if ev.button==MouseButton.LEFT then
          if not state.moved2 then
            local px = math.floor((ev.x - state.offX2) / state.zoom2)
            local py = math.floor((ev.y - state.offY2) / state.zoom2)

            if px>=0 and px<state.preview2.width
              and py>=0 and py<state.preview2.height then

              app.fgColor   = Color{ r=px, g=py, b=0, a=255 }
              state.selX2, state.selY2 = px, py
            end
          end
          dlg:repaint()
        end

        if ev.button == MouseButton.MIDDLE then
          state.drag2  = false
          state.moved2 = false
        end
      end,
    }

    dlg:button{
      id = "reset",
      text = "Reset",
      onclick = function()
        state.zoom2 = 1.0
        state.offX2 = 0
        state.offY2 = 0
        state.selX2 = nil
        state.selY2 = nil
        dlg:repaint()
      end
    }

    dlg:button{
      text = "Close",
      onclick = function()
        dlg:close()
        state.dlg2 = nil
        if not state.dlg1 then
          cleanupWatchers()
        end
      end
    }

    dlg:show{ wait=false }
    state.dlg2 = dlg
  end

  function installWatcher()
    if not state.baseSprite then return end
    if state.watcherId then
      state.baseSprite.events:off(state.watcherId)
      state.watcherId = nil
    end

    state.watcherId = state.baseSprite.events:on('change', function()
      makePreview1()
      if state.dlg1 then state.dlg1:repaint() else showDialog1() end
      if state.dlg2 then state.dlg2:repaint() end
    end)
  end

  function installSiteWatcher()
    -- remove old one if you re‑run the script
    if state.siteWatcherId then
      app.events:off(state.siteWatcherId)
      state.siteWatcherId = nil
    end

    state.siteWatcherId = app.events:on('sitechange', function()
      -- rebuild preview 1 with the new active layer / frame
      makePreview1()

      -- redraw dialog‑1 immediately (if it’s open)
      if state.dlg1 then state.dlg1:repaint() else showDialog1() end
    end)
  end

  function cleanupWatchers()
    if state.watcherId then
      state.baseSprite.events:off(state.watcherId)
      state.watcherId = nil
    end
    if state.siteWatcherId then
      app.events:off(state.siteWatcherId)
      state.siteWatcherId = nil
    end
  end


  plugin:newCommand {
    id = "sprite_map_helper_id",
    title = "Sprite Map Helper",
    group = "edit_insert",
    onclick=function()
      if pickOverlay() then
        makePreview1()
        makePreview2()
        showDialog1()
        showDialog2()
        installWatcher()
        installSiteWatcher()
      end
    end,
    onenabled=function()
      return true
    end
  }


end

function exit(plugin)
end