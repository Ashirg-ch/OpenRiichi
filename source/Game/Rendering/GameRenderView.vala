using Engine;
using Gee;

public class GameRenderView : View3D, IGameRenderer
{
    private RenderTile[] tiles { get { return scene.tiles; } }
    private RenderPlayer[] players { get { return scene.players; } }

    private GameScene scene;
    private RenderTile? mouse_down_tile;
    private ArrayList<TileSelectionGroup>? select_groups = null;

    private Sound hover_sound;

    private RoundStartInfo info;
    private int observer_index;
    private int dealer_index;
    private Options options;
    private RoundScoreState score;
    private AnimationTimings timings;

    public GameRenderView(RoundStartInfo info, int observer_index, int dealer_index, Options options, RoundScoreState score, AnimationTimings timings)
    {
        this.info = info;
        this.observer_index = observer_index != -1 ? observer_index : 0;
        this.dealer_index = dealer_index;
        this.options = options;
        this.score = score;
        this.timings = timings;
    }

    public override void added()
    {
        scene = new GameScene(options, observer_index, dealer_index, info.wall_index, store.audio_player, score, timings);
        world.add_object(scene);

        var observer = scene.players[observer_index];
        observe_object = new WorldObject();
        observer.add_object(observe_object);

        WorldLight light1 = new WorldLight();
        WorldLight light2 = new WorldLight();
        WorldLight light3 = new WorldLight();
        observe_object.add_object(light1);
        observe_object.add_object(light2);
        observe_object.add_object(light3);

        light1.intensity = 12;
        light2.intensity = 8;
        light3.intensity = 8;
        light1.position = Vec3(  0, 20,  10);
        light2.position = Vec3( 15, 10, -10);
        light3.position = Vec3(-15, 10, -10);

        target = new WorldObject();
        observe_object.add_object(target);
        target.position = Vec3(0, -4, 0);

        camera = new TargetWorldCamera(target);
        observe_object.add_object(camera);
        world.active_camera = camera;
        camera.position = Vec3(0, 16, 10);
        camera.view_angle = 80;

        buffer_action(new RenderActionDelay(new AnimationTime.preset(0.5f)));
        buffer_action(new RenderActionSplitDeadWall(timings.split_wall));

        hover_sound = store.audio_player.load_sound("mouse_over");

        foreach (RenderTile tile in scene.tiles)
        {
            tile.on_mouse_over.connect(tile_hover);
            tile.on_focus_lost.connect(tile_unhover);
        }
        world.do_picking = true;

        for (int i = 0; i < 16; i++)
            buffer_action(new RenderActionInitialDraw(timings.initial_draw, players[(i + dealer_index) % 4], i < 12 ? 4 : 1));

        buffer_action(new RenderActionFlipDora());
    }

    WorldCamera camera;
    WorldObject target;
    WorldObject observe_object;

    protected override void key_press(KeyArgs key)
    {
        if (key.keycode == KeyCode.NUM_1)
        {
            camera.position = camera.position.plus(Vec3(0, 0.1f, 0));
            Environment.log(LogType.DEBUG, "GameRenderView", "Camera height: " + camera.position.y.to_string());
        }
        else if (key.keycode == KeyCode.NUM_2)
        {
            camera.position = camera.position.plus(Vec3(0, -0.1f, 0));
            Environment.log(LogType.DEBUG, "GameRenderView", "Camera height: " + camera.position.y.to_string());
        }
        else if (key.keycode == KeyCode.NUM_3)
        {
            target.position = target.position.plus(Vec3(0, 0.1f, 0));
            Environment.log(LogType.DEBUG, "GameRenderView", "Target height: " + target.position.y.to_string());
        }
        else if (key.keycode == KeyCode.NUM_4)
        {
            target.position = target.position.plus(Vec3(0, -0.1f, 0));
            Environment.log(LogType.DEBUG, "GameRenderView", "Target height: " + target.position.y.to_string());
        }
        if (key.keycode == KeyCode.NUM_5)
        {
            camera.view_angle += 0.5f;
            Environment.log(LogType.DEBUG, "GameRenderView", "Camera fov: " + camera.view_angle.to_string());
        }
        else if (key.keycode == KeyCode.NUM_6)
        {
            camera.view_angle -= 0.5f;
            Environment.log(LogType.DEBUG, "GameRenderView", "Camera fov: " + camera.view_angle.to_string());
        }
    }

    public void load_options(Options options)
    {
        scene.load_options(options);
    }

    public void observe_next()
    {
        observer_index = (observer_index + 1) % 4;
        observe_animate();
    }

    public void observe_prev()
    {
        observer_index = (observer_index + 3) % 4;
        observe_animate();
    }

    private void observe_animate()
    {
        var observer = scene.players[observer_index];
        observer.convert_object(observe_object);

        WorldObjectAnimation animation = new WorldObjectAnimation(new AnimationTime.preset(2));
        PathQuat rot = new LinearPathQuat(Quat());
        animation.do_absolute_rotation(rot);

        animation.curve = new SCurve(0.5f);
        
        observe_object.cancel_buffered_animations();
        observe_object.animate(animation, true);

        foreach (var player in players)
            player.set_observed( player == observer);
    }

    private void game_finished(RoundFinishResult results)
    {
        switch (results.result)
        {
        case RoundFinishResult.RoundResultEnum.DRAW:
            draw(results.tenpai_indices, results.draw_type);
            break;
        case RoundFinishResult.RoundResultEnum.RON:
            ron(results.winner_indices, results.loser_index, results.discard_tile, results.riichi_return_index, true);
            break;
        case RoundFinishResult.RoundResultEnum.TSUMO:
            tsumo(results.winner_indices[0]);
            break;
        }
    }

    private void ron(int[] winner_indices, int discard_player_index, int tile_ID, int return_riichi_index, bool allow_dora_flip)
    {
        RenderPlayer? discard_player = null;
        if (discard_player_index != -1)
            discard_player = players[discard_player_index];

        RenderPlayer? return_riichi_player = null;
        if (return_riichi_index != -1)
            return_riichi_player = players[return_riichi_index];

        RenderTile? tile = null;

        if (tile_ID != -1)
        {
            tile = tiles[tile_ID];
            discard_player.rob_tile(tile);
        }

        RenderPlayer[] winners = new RenderPlayer[winner_indices.length];
        for (int i = 0; i < winners.length; i++)
            winners[i] = players[winner_indices[i]];

        buffer_action(new RenderActionRon(timings.win, winners, discard_player, tile, return_riichi_player, allow_dora_flip));
    }

    private void tsumo(int player_index)
    {
        RenderPlayer player = players[player_index];
        buffer_action(new RenderActionTsumo(timings.win, player));
    }

    private void draw(int[] tenpai_indices, GameDrawType draw_type)
    {
        if (draw_type == GameDrawType.TRIPLE_RON)
        {
            ron(tenpai_indices, -1, -1, -1, false);
            return;
        }

        if (draw_type == GameDrawType.EMPTY_WALL ||
            draw_type == GameDrawType.FOUR_RIICHI ||
            draw_type == GameDrawType.VOID_HAND ||
            draw_type == GameDrawType.TRIPLE_RON)
        {
            ArrayList<RenderPlayer> tenpai_players = new ArrayList<RenderPlayer>();
            foreach (int i in tenpai_indices)
                tenpai_players.add(players[i]);

            buffer_action(new RenderActionGameDraw(new AnimationTime.zero(), tenpai_players, draw_type));
        }
    }

    private void tile_assignment(Tile tile)
    {
        RenderTile t = tiles[tile.ID];
        t.tile_type = tile;
        t.reload();
    }

    private void tile_draw(int player_index)
    {
        RenderPlayer player = players[player_index];
        buffer_action(new RenderActionDraw(timings.tile_draw, player));
    }

    public void dead_tile_draw(int player_index)
    {
        RenderPlayer player = players[player_index];
        buffer_action(new RenderActionDrawDeadWall(timings.tile_draw, player));
    }

    private void tile_discard(int player_index, int tile_ID)
    {
        RenderPlayer player = players[player_index];
        RenderTile tile = tiles[tile_ID];
        buffer_action(new RenderActionDiscard(timings.tile_discard, player, tile));
    }

    private void flip_dora()
    {
        scene.wall.flip_dora();
    }

    private void riichi(int player_index, bool open)
    {
        RenderPlayer player = players[player_index];
        buffer_action(new RenderActionRiichi(timings.riichi, player, open));
    }

    private void late_kan(int player_index, int tile_ID)
    {
        RenderPlayer player = players[player_index];
        RenderTile tile = tiles[tile_ID];
        buffer_action(new RenderActionLateKan(timings.call, player, tile));
    }

    private void closed_kan(int player_index, TileType type)
    {
        RenderPlayer player = players[player_index];
        buffer_action(new RenderActionClosedKan(timings.call, player, type));
    }

    private void open_kan(int player_index, int discard_player_index, int tile_ID, int tile_1_ID, int tile_2_ID, int tile_3_ID)
    {
        RenderPlayer player = players[player_index];
        RenderPlayer discard_player = players[discard_player_index];

        RenderTile tile   = tiles[tile_ID];
        RenderTile tile_1 = tiles[tile_1_ID];
        RenderTile tile_2 = tiles[tile_2_ID];
        RenderTile tile_3 = tiles[tile_3_ID];

        buffer_action(new RenderActionOpenKan(timings.call, player, discard_player, tile, tile_1, tile_2, tile_3));

        dead_tile_draw(player_index);
    }

    private void pon(int player_index, int discard_player_index, int tile_ID, int tile_1_ID, int tile_2_ID)
    {
        RenderPlayer player = players[player_index];
        RenderPlayer discard_player = players[discard_player_index];

        RenderTile tile   = tiles[tile_ID];
        RenderTile tile_1 = tiles[tile_1_ID];
        RenderTile tile_2 = tiles[tile_2_ID];

        buffer_action(new RenderActionPon(timings.call, player, discard_player, tile, tile_1, tile_2));
    }

    private void chii(int player_index, int discard_player_index, int tile_ID, int tile_1_ID, int tile_2_ID)
    {
        RenderPlayer player = players[player_index];
        RenderPlayer discard_player = players[discard_player_index];

        RenderTile tile   = tiles[tile_ID];
        RenderTile tile_1 = tiles[tile_1_ID];
        RenderTile tile_2 = tiles[tile_2_ID];

        buffer_action(new RenderActionChii(timings.call, player, discard_player, tile, tile_1, tile_2));
    }

    public void set_active(bool active)
    {
        if (active)
            buffer_action(new RenderActionSetActive(active));
        else
            scene.active = active;

        if (!active)
        {
            select_groups = null;
            foreach (RenderTile tile in tiles)
                tile.indicated = false;
        }
    }

    /////////////////////

    private void buffer_action(RenderAction action)
    {
        scene.add_action(action);
    }

    private RenderTile? hover_tile = null;
    private void tile_hover(WorldObject obj)
    {
        hover_tile = obj as RenderTile;
    }

    private void tile_unhover(WorldObject obj)
    {
        (obj as RenderTile).hovered = false;
        hover_tile = null;

        //if (scene.active)
            foreach (var tile in tiles)
                tile.indicated = false;
    }

    protected override void mouse_move(MouseMoveArgs mouse)
    {
        base.mouse_move(mouse);

        RenderTile? tile = scene.active ? hover_tile : null;
        TileSelectionGroup? group = get_tile_selection_group(tile);

        if (group != null)
        {
            if (!tile.hovered)
                hover_sound.play();
            foreach (Tile t in group.highlight_tiles)
                tiles[t.ID].indicated = true;

            tile.hovered = true;
            mouse.cursor_type = CursorType.HOVER;
            mouse.handled = true;
        }
    }

    private TileSelectionGroup? get_tile_selection_group(RenderTile? tile)
    {
        if (tile == null || select_groups == null)
            return null;

        foreach (TileSelectionGroup group in select_groups)
            foreach (Tile t in group.selection_tiles)
                if (t.ID == tile.tile_type.ID)
                    return group;

        return null;
    }

    protected override void mouse_event(MouseEventArgs mouse)
    {
        if (mouse.handled || !scene.active)
        {
            mouse_down_tile = null;
            return;
        }

        if (mouse.button == MouseEventArgs.Button.LEFT)
        {
            RenderTile? tile = get_tile_selection_group(hover_tile) == null ? null : hover_tile;

            if (mouse.down)
                mouse_down_tile = tile;
            else
            {
                if (tile != null && tile == mouse_down_tile)
                    tile_selected(tile.tile_type);

                mouse_down_tile = null;
            }
        }
    }

    public void set_tile_select_groups(ArrayList<TileSelectionGroup>? groups)
    {
        /*foreach (RenderTile tile in scene.tiles)
            tile.indicated = false;*/

        select_groups = groups;

        /*if (groups != null)
            foreach (TileSelectionGroup group in groups)
                if (group.group_type != TileSelectionGroup.GroupType.DISCARD)
                    foreach (Tile tile in group.highlight_tiles)
                        tiles[tile.ID].indicated = true;*/
    }
}
